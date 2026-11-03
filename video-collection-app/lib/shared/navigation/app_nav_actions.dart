import '../ui/kit.dart';

/// 跨层导航动作:shared widgets 不直接 import 端页面,
/// 由两端 App 注入具体页面工厂。
class AppNavActions extends InheritedWidget {
  /// 打开账号 / 登录页
  final Future<void> Function(BuildContext context) openAccount;

  /// 打开资讯 / 社区详情
  final void Function(
    BuildContext context, {
    required String kind,
    required int contentId,
  }) openContentDetail;

  /// 打开 Wiki 词条
  final void Function(BuildContext context, {required int subjectId})
      openWikiSubject;

  /// 构建设置页(供 `--open-settings` 直达)
  final WidgetBuilder settingsBuilder;

  const AppNavActions({
    super.key,
    required this.openAccount,
    required this.openContentDetail,
    required this.openWikiSubject,
    required this.settingsBuilder,
    required super.child,
  });

  static AppNavActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppNavActions>();

  static AppNavActions of(BuildContext context) {
    final actions = maybeOf(context);
    assert(actions != null, '缺少 AppNavActions: 入口必须注入端专属导航工厂');
    return actions!;
  }

  @override
  bool updateShouldNotify(AppNavActions oldWidget) => false;
}
