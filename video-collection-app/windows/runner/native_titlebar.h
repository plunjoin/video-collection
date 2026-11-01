#ifndef RUNNER_NATIVE_TITLEBAR_H_
#define RUNNER_NATIVE_TITLEBAR_H_

#include <windows.h>

// 右上角原生窗口控制条：最小化 / 最大化(还原) / 关闭 三联按钮。
// 以分层子窗口（per-pixel alpha）绘制在 Flutter 内容之上，替代被移除的
// Dart 自定义标题栏；按钮动作直接投递系统命令到主窗口。
namespace native_titlebar {

// 逻辑尺寸（96 DPI 基准）。
constexpr int kBarHeight = 32;
constexpr int kButtonWidth = 46;
constexpr int kButtonCount = 3;

// 在主窗口右上角创建控制条子窗口（需在 Flutter 内容窗口之后创建以保证置顶）。
HWND Create(HWND parent, double scale);

// 依据主窗口当前客户区/DPI 把控制条贴到右上角，并刷新最大化状态。
void UpdateLayout(HWND bar, HWND parent);

// 重绘（悬停/激活态/最大化状态变化后调用）。
void Repaint(HWND bar);

// 同步应用明暗主题（按钮配色跟随）。
void SetDarkTheme(HWND bar, bool dark);

}  // namespace native_titlebar

#endif  // RUNNER_NATIVE_TITLEBAR_H_
