import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'brand_widgets.dart';

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
                ? Theme.of(context).colorScheme.primary
                : (dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            minimumSize: const Size(44, 38),
            tapTargetSize: MaterialTapTargetSize.padded,
            backgroundColor: selected
                ? Theme.of(context).colorScheme.primary
                      .withValues(alpha: dark ? .22 : .08)
                : (dark ? const Color(0xFF222E43) : const Color(0xFFF4F7FF)),
            side: BorderSide(
              color: selected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: .35)
                  : Colors.transparent,
            ),
            shape: const StadiumBorder(),
            textStyle: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
  Size get preferredSize => const Size.fromHeight(58);
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 3, 16, 7),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: dark ? AppColors.darkCard : const Color(0xFFF3F5FE),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: List.generate(tabs.length, (index) {
              final selected = controller.index == index;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  child: InkWell(
                    onTap: () => controller.animateTo(index),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: selected
                            ? LinearGradient(
                                colors: dark
                                    ? [
                                        const Color(0xFF38405B),
                                        const Color(0xFF443750),
                                      ]
                                    : [Colors.white, const Color(0xFFFFF5FC)],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: selected
                            ? const [
                                BoxShadow(
                                  color: Color(0x0C667AAE),
                                  blurRadius: 7,
                                  offset: Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: DefaultTextStyle(
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : (dark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          child: tabs[index],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
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
  Size get preferredSize =>
      Size.fromHeight(64 + (bottom?.preferredSize.height ?? 0));
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: IconTheme(
        data: Theme.of(context).appBarTheme.iconTheme ?? const IconThemeData(),
        child: Material(
          color: dark ? AppColors.darkBg : Colors.white,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 64,
                  child: Padding(
                    padding: EdgeInsets.only(left: titleSpacing, right: 12),
                    child: Row(
                      children: [
                        if (Navigator.of(context).canPop()) ...[
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            tooltip: '返回',
                            icon: const Icon(
                              Icons.chevron_left_rounded,
                              size: 25,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: dark
                                  ? AppColors.darkCard
                                  : AppColors.primary50,
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
  const BrandPageBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.eyebrow,
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      padding: const EdgeInsets.all(20),
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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      child: Container(
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
            Flexible(
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
      ),
    );
  }
}

/// Branded option dialog used for sort order and player speed.
Future<T?> showBrandOptions<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => BrandDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: options
            .map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: BrandPill(
                    label: Text(option.$2),
                    selected: selected == option.$1,
                    onPressed: () => Navigator.of(context).pop(option.$1),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );
}
