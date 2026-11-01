#include "native_titlebar.h"

#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace native_titlebar {
namespace {

constexpr wchar_t kBarClassName[] = L"BLLII_WINDOW_CONTROLS_BAR";

// 品牌色：关闭悬停使用与客户端一致的玫红。
constexpr COLORREF kCloseHover = RGB(0xF4, 0x3F, 0x5E);

enum ButtonId { kMinimize = 0, kMaximize = 1, kClose = 2 };

struct BarState {
  // owner = 顶层主窗口（SC_ 命令/缩放/激活态都以它为准）
  HWND owner = nullptr;
  bool dark = true;
  bool maximized = false;
  int hover_index = -1;
  int pressed_index = -1;
};

BarState* StateOf(HWND hwnd) {
  return reinterpret_cast<BarState*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
}

double ScaleOf(HWND owner) {
  UINT dpi = GetDpiForWindow(owner);
  if (dpi == 0) dpi = USER_DEFAULT_SCREEN_DPI;
  return dpi / 96.0;
}

int Scaled(int logical, double scale) {
  return static_cast<int>(logical * scale);
}

int HitIndex(BarState* state, POINT pt) {
  if (pt.y < 0 || pt.y >= Scaled(kBarHeight, ScaleOf(state->owner))) {
    return -1;
  }
  if (pt.x < 0) return -1;
  int bw = Scaled(kButtonWidth, ScaleOf(state->owner));
  int index = pt.x / bw;
  if (index < 0 || index >= kButtonCount) return -1;
  return index;
}

// 像素写入：premultiplied ARGB。
void BlendPixel(std::uint32_t* bits, int w, int h, int x, int y,
                COLORREF color, int alpha) {
  if (x < 0 || y < 0 || x >= w || y >= h) return;
  std::uint32_t* p = bits + static_cast<size_t>(y) * w + x;
  int src_r = GetRValue(color);
  int src_g = GetGValue(color);
  int src_b = GetBValue(color);
  // premultiply
  int pr = src_r * alpha / 255;
  int pg = src_g * alpha / 255;
  int pb = src_b * alpha / 255;
  // alpha-over 叠加（背景已是 premultiplied）
  int dst_a = (*p >> 24) & 0xFF;
  int out_a = alpha + dst_a * (255 - alpha) / 255;
  int out_r = pr + ((*p & 0xFF) * (255 - alpha)) / 255;
  int out_g = pg + (((*p >> 8) & 0xFF) * (255 - alpha)) / 255;
  int out_b = pb + (((*p >> 16) & 0xFF) * (255 - alpha)) / 255;
  *p = (static_cast<std::uint32_t>(out_a) << 24) |
       (static_cast<std::uint32_t>(out_b) << 16) |
       (static_cast<std::uint32_t>(out_g) << 8) |
       static_cast<std::uint32_t>(out_r);
}

// 1px 粗细的线段（带端点舍入，观感接近原生标题栏字形）。
void DrawLine(std::uint32_t* bits, int w, int h, float x1, float y1, float x2,
              float y2, COLORREF color, int alpha) {
  const float dx = x2 - x1;
  const float dy = y2 - y1;
  const int steps = static_cast<int>(
      std::max(std::fabs(dx), std::fabs(dy)) * 2.0f + 1.0f);
  for (int i = 0; i <= steps; i++) {
    float t = static_cast<float>(i) / steps;
    int x = static_cast<int>(std::lround(x1 + dx * t));
    int y = static_cast<int>(std::lround(y1 + dy * t));
    BlendPixel(bits, w, h, x, y, color, alpha);
    // 轻微加粗，抗锯齿感
    BlendPixel(bits, w, h, x + 1, y, color, alpha / 2);
    BlendPixel(bits, w, h, x, y + 1, color, alpha / 2);
  }
}

void DrawRect(std::uint32_t* bits, int w, int h, float x1, float y1, float x2,
              float y2, COLORREF color, int alpha) {
  DrawLine(bits, w, h, x1, y1, x2, y1, color, alpha);
  DrawLine(bits, w, h, x2, y1, x2, y2, color, alpha);
  DrawLine(bits, w, h, x2, y2, x1, y2, color, alpha);
  DrawLine(bits, w, h, x1, y2, x1, y1, color, alpha);
}

void PaintBar(HWND hwnd, BarState* state) {
  RECT rc;
  if (!GetClientRect(hwnd, &rc)) return;
  int w = rc.right - rc.left;
  int h = rc.bottom - rc.top;
  if (w <= 0 || h <= 0) return;

  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = w;
  bmi.bmiHeader.biHeight = -h;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  HDC hdc_window = GetDC(hwnd);
  if (!hdc_window) return;
  HDC mem = CreateCompatibleDC(hdc_window);
  void* bits = nullptr;
  HBITMAP bmp = CreateDIBSection(hdc_window, &bmi, DIB_RGB_COLORS, &bits,
                                 nullptr, 0);
  HBITMAP old = reinterpret_cast<HBITMAP>(SelectObject(mem, bmp));
  if (bits) {
    memset(bits, 0, static_cast<size_t>(w) * h * 4);
    auto* px = static_cast<std::uint32_t*>(bits);

    // 关键：alpha=0 的像素对鼠标完全穿透（分层窗口逐像素命中测试），
    // 只有图标线条能命中会让三联按钮"点不到"。
    // 整条铺一层 alpha=1（约 0.4% 不透明度，肉眼不可见）让整个矩形都可命中。
    for (size_t i = 0; i < static_cast<size_t>(w) * h; i++) {
      px[i] = 0x01000000u;  // premultiplied A=1, RGB=0
    }

    double scale = ScaleOf(state->owner);
    int bw = Scaled(kButtonWidth, scale);
    int bh = Scaled(kBarHeight, scale);
    bool active = GetActiveWindow() == state->owner;

    for (int i = 0; i < kButtonCount; i++) {
      bool hover = state->hover_index == i;
      bool pressed = state->pressed_index == i && hover;
      int x0 = i * bw;

      // 悬停/按下底色
      if (hover) {
        COLORREF fill = (i == kClose) ? kCloseHover
                        : state->dark ? RGB(0xFF, 0xFF, 0xFF)
                                     : RGB(0x1E, 0x29, 0x3B);
        int base_alpha = state->dark ? 36 : 30;
        int alpha = pressed ? base_alpha + 26 : base_alpha;
        if (i == kClose) alpha = pressed ? 255 : 235;
        for (int y = 2; y < bh - 2; y++) {
          for (int x = x0 + 2; x < (i + 1) * bw - 2; x++) {
            BlendPixel(px, w, h, x, y, fill, alpha);
          }
        }
      }

      // 图形颜色：悬停于关闭键时白色，其余按主题
      COLORREF glyph = state->dark ? RGB(0xFF, 0xFF, 0xFF) : RGB(0x1E, 0x29, 0x3B);
      int glyph_alpha = active ? 215 : 130;
      if (hover) {
        glyph_alpha = (i == kClose) ? 255 : (state->dark ? 255 : 235);
      }

      float cx = x0 + bw / 2.0f;
      float cy = bh / 2.0f;
      float r = 4.5f;  // 字形半径（逻辑像素 × DPI 后绘制）
      float sx = static_cast<float>(bw) / kButtonWidth;
      float sy = static_cast<float>(bh) / kBarHeight;
      float gr = r * ((sx + sy) / 2.0f);

      if (i == kMinimize) {
        DrawLine(px, w, h, cx - gr, cy, cx + gr, cy, glyph, glyph_alpha);
      } else if (i == kMaximize) {
        if (state->maximized) {
          // 还原：两个错位矩形
          DrawRect(px, w, h, cx - gr, cy - gr + 2, cx + gr - 2, cy + gr - 2,
                   glyph, glyph_alpha);
          DrawRect(px, w, h, cx - gr + 2, cy - gr + 4, cx + gr, cy + gr + 0.5f,
                   glyph, glyph_alpha);
        } else {
          DrawRect(px, w, h, cx - gr, cy - gr, cx + gr, cy + gr, glyph,
                   glyph_alpha);
        }
      } else {
        float g = gr * 0.78f;
        DrawLine(px, w, h, cx - g, cy - g, cx + g, cy + g, glyph, glyph_alpha);
        DrawLine(px, w, h, cx + g, cy - g, cx - g, cy + g, glyph, glyph_alpha);
      }
    }
  }

  POINT src = {0, 0};
  SIZE size = {w, h};
  BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  UpdateLayeredWindow(hwnd, hdc_window, nullptr, &size, mem, &src, 0, &blend,
                      ULW_ALPHA);

  SelectObject(mem, old);
  DeleteObject(bmp);
  DeleteDC(mem);
  ReleaseDC(hwnd, hdc_window);
}

void SubmitButton(HWND hwnd, BarState* state, int index) {
  // 系统命令必须投递到顶层主窗口（按钮条可能挂在 Flutter 视图之下）
  HWND owner = state->owner;
  switch (index) {
    case kMinimize:
      PostMessageW(owner, WM_SYSCOMMAND, SC_MINIMIZE, 0);
      break;
    case kMaximize:
      PostMessageW(owner, WM_SYSCOMMAND,
                   IsZoomed(owner) ? SC_RESTORE : SC_MAXIMIZE, 0);
      break;
    case kClose:
      PostMessageW(owner, WM_SYSCOMMAND, SC_CLOSE, 0);
      break;
    default:
      break;
  }
}

LRESULT CALLBACK BarWndProc(HWND hwnd, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  BarState* state = StateOf(hwnd);
  if (!state) {
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
  switch (message) {
    case WM_MOUSEMOVE: {
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      int index = HitIndex(state, pt);
      if (state->hover_index != index) {
        state->hover_index = index;
        PaintBar(hwnd, state);
      }
      TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE, hwnd, 0};
      TrackMouseEvent(&track);
      return 0;
    }
    case WM_MOUSELEAVE: {
      state->hover_index = -1;
      state->pressed_index = -1;
      PaintBar(hwnd, state);
      return 0;
    }
    case WM_LBUTTONDOWN: {
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      state->pressed_index = HitIndex(state, pt);
      SetCapture(hwnd);
      PaintBar(hwnd, state);
      return 0;
    }
    case WM_LBUTTONUP: {
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      int index = HitIndex(state, pt);
      int pressed = state->pressed_index;
      state->pressed_index = -1;
      if (GetCapture() == hwnd) ReleaseCapture();
      PaintBar(hwnd, state);
      // 在同一按钮上按下并抬起才触发，避免误触
      if (pressed >= 0 && index == pressed) {
        SubmitButton(hwnd, state, index);
      }
      return 0;
    }
    case WM_PAINT: {
      ValidateRect(hwnd, nullptr);
      PaintBar(hwnd, state);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_DESTROY: {
      delete state;
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
      return 0;
    }
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace

HWND Create(HWND parent, double scale) {
  WNDCLASSW wc = {};
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  wc.lpszClassName = kBarClassName;
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = BarWndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  if (!GetClassInfoW(wc.hInstance, kBarClassName, &wc)) {
    RegisterClassW(&wc);
  }

  int w = Scaled(kButtonWidth * kButtonCount, scale);
  int h = Scaled(kBarHeight, scale);
  HWND bar = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST, kBarClassName, L"",
                             WS_CHILD | WS_CLIPSIBLINGS, 0, 0, w, h, parent,
                             nullptr, GetModuleHandleW(nullptr), nullptr);
  if (!bar) return nullptr;
  auto* state = new BarState();
  state->owner = GetAncestor(parent, GA_ROOT);
  state->dark = true;
  SetWindowLongPtrW(bar, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
  return bar;
}

void UpdateLayout(HWND bar, HWND parent) {
  BarState* state = StateOf(bar);
  if (!state) return;
  state->owner = GetAncestor(parent, GA_ROOT);
  state->maximized = IsZoomed(state->owner) != FALSE;

  // 按钮条挂在 Flutter 视图之下时，按其直接父窗口客户区定位；
  // 直接挂在主窗口时等价于主窗口客户区。
  HWND actualParent = GetParent(bar);
  if (!actualParent) actualParent = parent;
  RECT rc;
  GetClientRect(actualParent, &rc);
  double scale = ScaleOf(state->owner);
  int w = Scaled(kButtonWidth * kButtonCount, scale);
  int h = Scaled(kBarHeight, scale);
  MoveWindow(bar, rc.right - w, rc.top, w, h, FALSE);
  Repaint(bar);
}

void Repaint(HWND bar) {
  BarState* state = StateOf(bar);
  if (!state) return;
  state->maximized = IsZoomed(state->owner) != FALSE;
  PaintBar(bar, state);
}

void SetDarkTheme(HWND bar, bool dark) {
  BarState* state = StateOf(bar);
  if (!state) return;
  if (state->dark != dark) {
    state->dark = dark;
    PaintBar(bar, state);
  }
}

}  // namespace native_titlebar
