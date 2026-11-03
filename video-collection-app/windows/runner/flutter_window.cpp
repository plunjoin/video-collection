#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <windowsx.h>

#include <cstdio>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "native_titlebar.h"

namespace {

// 顶部边缘原生缩放热区高度（物理像素）：WM_NCCALCSIZE 在 Win11 未给顶边
// 预留非客户区，这里在 Flutter 视图子窗口上补出 HTTOP，否则顶边无法拉伸窗口。
constexpr int kTopResizeGripPx = 6;

constexpr wchar_t kViewProcProp[] = L"BlliiOriginalViewProc";

// 顶部系统拖拽带开关。
// 拖拽带已收缩：整条 34px 的 HTCAPTION 会把页面头部的返回键
// 一并吃掉（点击到不了 Flutter）。窗口拖拽改由各页面头部的
// WindowDragArea 承担，这里只保留最顶缘的原生缩放热区。
// 全屏播放时通过 bllii/native_window 的 setControlsVisible(false) 关闭。
bool g_caption_band_enabled = true;

LRESULT CALLBACK FlutterViewSubclassProc(HWND hwnd, UINT message,
                                         WPARAM wparam, LPARAM lparam) {
  auto original = reinterpret_cast<WNDPROC>(
      GetPropW(hwnd, kViewProcProp));
  if (message == WM_NCHITTEST && original) {
    HWND root = GetAncestor(hwnd, GA_ROOT);
    if (root && g_caption_band_enabled) {
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(hwnd, &pt);
      // 最顶 6px 作为上边框缩放手柄（最大化时无意义）。
      // 不再把整条顶部让位带标成 HTCAPTION：那会吞掉头部返回键的点击。
      if (!IsZoomed(root) && pt.y >= 0 && pt.y < kTopResizeGripPx) {
        return HTTOP;
      }
    }
  }
  if (message == WM_NCDESTROY) {
    RemovePropW(hwnd, kViewProcProp);
  }
  if (!original) {
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
  return CallWindowProc(original, hwnd, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // 子类化 Flutter 视图：补出窗口顶边的原生缩放热区（见 kTopResizeGripPx）。
  // Dart 侧不再绘制标题栏，窗口拖拽由页面头部/播放器顶栏的拖拽区承担。
  HWND view = flutter_controller_->view()->GetNativeWindow();
  if (view && !GetPropW(view, kViewProcProp)) {
    auto original = SetWindowLongPtrW(view, GWLP_WNDPROC,
                                      reinterpret_cast<LONG_PTR>(
                                          FlutterViewSubclassProc));
    SetPropW(view, kViewProcProp, reinterpret_cast<HANDLE>(original));
  }

  // 右上角原生窗口控制条（最小化 / 最大化 / 关闭），替代移除的 Dart 标题栏。
  // 挂在 Flutter 视图之下作为其唯一子窗口：引擎刷新 Z 序也不会盖住它，
  // 输入与绘制天然位于 Flutter 内容之上。
  UINT dpi = FlutterDesktopGetDpiForHWND(GetHandle());
  controls_bar_ = native_titlebar::Create(view, dpi / 96.0);
  if (controls_bar_) {
    native_titlebar::UpdateLayout(controls_bar_, GetHandle());
    ShowWindow(controls_bar_, SW_SHOWNOACTIVATE);
  }

  // bllii/native_window：Dart 同步应用主题（按钮配色）与全屏状态（隐藏控制条）。
  native_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "bllii/native_window",
          &flutter::StandardMethodCodec::GetInstance());
  native_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name().compare("setTheme") == 0) {
          bool dark = std::get_if<bool>(call.arguments()) != nullptr &&
                      std::get<bool>(*call.arguments());
          if (controls_bar_) native_titlebar::SetDarkTheme(controls_bar_, dark);
          result->Success();
        } else if (call.method_name().compare("setControlsVisible") == 0) {
          bool visible = std::get_if<bool>(call.arguments()) != nullptr &&
                         std::get<bool>(*call.arguments());
          g_caption_band_enabled = visible;
          if (controls_bar_) {
            ShowWindow(controls_bar_,
                       visible ? SW_SHOWNOACTIVATE : SW_HIDE);
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  controls_bar_ = nullptr;

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  LRESULT handled = Win32Window::MessageHandler(hwnd, message, wparam, lparam);

  // 尺寸/DPI/激活状态变化后，把原生控制条重新贴到右上角并刷新绘制。
  if (controls_bar_ &&
      (message == WM_SIZE || message == WM_DPICHANGED ||
       message == WM_ACTIVATE)) {
    native_titlebar::UpdateLayout(controls_bar_, hwnd);
  }

  return handled;
}
