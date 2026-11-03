/// 全局间距标尺(4/8 栅格)。
///
/// 页面留白、卡片内距、组件间隙都从这里取值,不再手写魔法数字。
/// 数值即语义:同一档位在全局保持一致,跨页面才不会各漂各的。
abstract final class AppSpacing {
  /// 微间距:图标与文字、徽标内距。
  static const double xs = 4;

  /// 紧凑间隙:相关元素之间。
  static const double sm = 8;

  /// 列表项间距、小卡片内距。
  static const double md = 12;

  /// 默认组件内距、页面水平留白(紧凑布局)。
  static const double lg = 16;

  /// 卡片内距、宽松页面留白的补充档。
  static const double xl = 20;

  /// 页面水平留白(宽松布局)、区块间距。
  static const double xxl = 24;

  /// 大区块之间的分隔。
  static const double xxxl = 32;
}
