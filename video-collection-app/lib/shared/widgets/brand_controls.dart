import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import '../ui/kit.dart';
import 'package:flutter/services.dart';

import './brand_widgets.dart';
import '../theme/brand_icons.dart';
import '../utils/responsive.dart';
import './window_drag_area.dart';

/// 页面头部高度:标题与返回键所在的那一条,各平台统一 48px。
const double kAppHeaderHeight = 48.0;

/// Windows 原生最小化/最大化/关闭按钮区(138×32,悬浮于内容之上)。
/// 头部右侧有操作按钮的页面需预留此宽度避免重叠。
final double kNativeWindowButtonsZone =
    (!kIsWeb && Platform.isWindows) ? 148.0 : 0.0;

/// Windows 桌面端顶部让位高度。
///
/// 窗口最顶缘有一条原生缩放热区,且右上角悬浮着原生最小化/最大化/关闭
/// 按钮。头部内容从这条让位带之下开始排,返回键才不会被原生区域挡住、
/// 也无法点击。其他平台为 0(状态栏由 SafeArea 处理)。
final double kBrandAppBarTopInset =
    (!kIsWeb && Platform.isWindows) ? 34.0 : 0.0;

/// Compact, explicitly styled selection controls shared by filters and sources.
class BrandPill extends StatelessWidget {
  final Widget label;
  final bool selected;
  final bool onDark;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onPressed;
  const BrandPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.onPressed,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    final enabled = onSelected != null || onPressed != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: TextButton(
          onPressed: enabled
              ? () {
                  onSelected?.call(!selected);
                  onPressed?.call();
                }
              : null,
          style: TextButton.styleFrom(
            foregroundColor: selected
                ? Colors.white
                : (dark
                      ? AppColors.darkTextSecondary
                      : AppColors.muted),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            minimumSize: const Size(36, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: selected
                ? AppColors.brandSolid
                : (dark ? const Color(0xFF1E2433) : const Color(0xFFF1F5F9)),
            side: BorderSide.none,
            shape: const StadiumBorder(),
            alignment: Alignment.center,
            textStyle: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              height: 1.2,
            ),
          ),
          child: label,
        ),
      ),
    );
  }
}

class BrandTabs extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<Widget> tabs;
  const BrandTabs({super.key, required this.controller, required this.tabs});
  @override
  Size get preferredSize => const Size.fromHeight(48);
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: dark ? AppColors.darkBorder : AppColors.line,
          ),
        ),
        child: TabBar(
          controller: controller,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: dark ? const Color(0xFF26324A) : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: dark ? 0.3 : 0.05,
                ),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          labelColor: dark ? Colors.white : AppColors.brandSolid,
          unselectedLabelColor:
              dark ? AppColors.darkTextSecondary : AppColors.muted,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: tabs.map((tab) => Tab(height: 32, child: tab)).toList(),
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
        ),
      ),
    );
  }
}

class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double titleSpacing;
  const BrandAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.titleSpacing = 16,
  });
  @override
  Size get preferredSize => Size.fromHeight(
      kBrandAppBarTopInset + kAppHeaderHeight + (bottom?.preferredSize.height ?? 0));
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: IconTheme(
        data: Theme.of(context).appBarTheme.iconTheme ?? const IconThemeData(),
        child: Container(
          color: dark ? AppColors.darkBg : Colors.white,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Windows 顶部让位带:原生缩放热区与右上角窗口按钮所在的
                // 区域,只作拖拽,不放可点击内容
                if (kBrandAppBarTopInset > 0)
                  SizedBox(
                    height: kBrandAppBarTopInset,
                    child: WindowDragArea(
                      enabled: true,
                      child: const SizedBox.expand(),
                    ),
                  ),
                // 头部(48px):返回键与标题垂直居中于此,
                // 空白处可拖拽(双击最大化,拖动窗口)
                SizedBox(
                  height: kAppHeaderHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: WindowDragArea(
                          enabled: kNativeWindowButtonsZone > 0,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: titleSpacing,
                          right: actions == null
                              ? 12
                              : (12 + (Responsive.isDesktop(context) ? kNativeWindowButtonsZone : 0.0)),
                        ),
                        child: Row(
                          children: [
                            if (Navigator.canPop(context)) ...[
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                tooltip: '返回',
                                icon: const BrandIcon(
                                  BIcons.chevronLeft,
                                  size: 25,
                                  monochrome: true,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: dark
                                      ? AppColors.darkCard
                                      : AppColors.primary50,
                                  minimumSize: const Size(40, 40),
                                  padding: EdgeInsets.zero,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: DefaultTextStyle(
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .5,
                                color: dark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              child: title,
                            ),
                          ),
                          ...?actions,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ?bottom,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BrandPageBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String eyebrow;

  /// 外边距。默认只保留上下节奏;水平留白由页面列表统一提供
  /// (列表 padding 已是 16 时不要再叠加,否则横幅会比同屏卡片多缩进 16)。
  final EdgeInsetsGeometry margin;
  const BrandPageBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    this.margin = const EdgeInsets.only(top: 8, bottom: 18),
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: dark
              ? [const Color(0xFF29324B), const Color(0xFF3A2F48)]
              : [
                  const Color(0xFFF0F5FF),
                  const Color(0xFFF6EFFF),
                  const Color(0xFFFFF0F8),
                ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.7,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.7,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const BrandLogo(width: 58, symbolOnly: true),
        ],
      ),
    );
  }
}

class BrandEmpty extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  const BrandEmpty({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Opacity(
            opacity: .65,
            child: BrandLogo(width: 86, symbolOnly: true),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 9),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.8,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}

/// 次要内容的侧边面板。
///
/// 桌面端从右侧滑入（side sheet），移动端从底部滑入（bottom sheet）。
/// 不可逆或账号安全类的确认仍用居中弹窗 [showDialog]，不走这里。
Future<T?> showBrandSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  if (Responsive.isDesktop(context)) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: _BrandSideSheet(child: Builder(builder: builder)),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }
  final bottomInset = MediaQuery.paddingOf(context).bottom;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottomInset),
      child: Builder(builder: builder),
    ),
  );
}

/// 桌面端右侧面板：全高、定宽，左侧圆角，超出可滚动。
class _BrandSideSheet extends StatelessWidget {
  final Widget child;
  const _BrandSideSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    return Material(
      color: dark ? AppColors.darkCard : Colors.white,
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.horizontal(
        left: Radius.circular(AppRadius.xxl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          minWidth: width < 420 ? width : 320,
        ),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: child,
          ),
        ),
      ),
    );
  }
}

class BrandDialog extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  const BrandDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.sizeOf(context).height * .78,
      ),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: dark ? AppColors.darkBorder : const Color(0xFFF0E8FA),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(23),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(25),
                ),
                gradient: LinearGradient(
                  colors: dark
                      ? [AppColors.darkCard, const Color(0xFF39314D)]
                      : [const Color(0xFFF2F6FF), const Color(0xFFFFF2FA)],
                ),
              ),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: dark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
                child: title,
              ),
            ),
            // 内容超出上限才滚动，否则按内容高度收缩。
            // 这里不能用 Flexible：弹窗路由给的是松约束，Flexible 会把
            // 内容区撑到最大高度，按钮下面留出大片空白。
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .5,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(23),
                child: content,
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
          ],
      ),
    );
  }
}

/// 选项面板：排序方式、播放倍速等次要选择。
/// 桌面端从右侧滑入，移动端从底部滑入。
Future<T?> showBrandOptions<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return showBrandSheet<T>(
    context,
    builder: (context) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: dark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 16),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BrandPill(
                label: Text(option.$2),
                selected: selected == option.$1,
                onPressed: () => Navigator.of(context).pop(option.$1),
              ),
            ),
        ],
      );
    },
  );
}
