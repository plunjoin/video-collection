/// 圆角标尺(与 web 端 CSS 严格对齐)。
///
/// 页面、卡片、胶囊、封面都从这里我们取值,不再手写魔法数字。
/// 数值即语义:同一档位在全局保持一致,跨页面才不会各漂各的。
///
/// 取值直接对照 `video-collection-service/web/portal/src/styles/*.css`:
/// - 视频封面 / 列表缩略图: `sm(8) · lg(14)`
/// - 卡片 / 面板: `md(12) · xl(16) · xxl(18) · 20(圆角容器)`
/// - 胶囊 / 按钮 / 筛选 chip: `pill(999)`(完全圆角)
abstract final class AppRadius {
  /// 直角:分隔线、零圆角修饰。
  static const double none = 0;

  /// 紧凑:标签角标、内部小元素。
  static const double sm = 8;

  /// 默认卡片圆角。
  static const double md = 12;

  /// 视频封面 / 列表缩略图圆角。
  static const double lg = 14;

  /// 宽松卡片 / 面板圆角。
  static const double xl = 16;

  /// 大圆角容器 / 对话框外框。
  static const double xxl = 18;

  /// 胶囊 / 按钮 / 筛选 chip:完全圆角。
  static const double pill = 999;
}
