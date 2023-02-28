import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class BrandLogo extends StatelessWidget {
  final double width;
  final bool symbolOnly;
  const BrandLogo({super.key, this.width = 112, this.symbolOnly = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      symbolOnly
          ? 'assets/brand/bllii-symbol.png'
          : 'assets/brand/bllii-horizontal${dark ? '-white' : ''}.png',
      width: width,
      height: symbolOnly ? width : width * 0.388,
      fit: BoxFit.contain,
      semanticLabel: 'bllii',
    );
  }
}

class BrandLoading extends StatelessWidget {
  final double size;
  const BrandLoading({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载',
    liveRegion: true,
    child: ClipOval(
      child: Image.asset(
        MediaQuery.disableAnimationsOf(context)
            ? 'assets/brand/bllii-symbol.png'
            : 'assets/brand/bllii-loading.gif',
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    ),
  );
}

class BrandButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData icon;
  const BrandButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon = Icons.play_arrow_rounded,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: onPressed == null ? null : AppColors.brandGradient,
      color: onPressed == null ? AppColors.lightBorder : null,
      borderRadius: BorderRadius.circular(28),
    ),
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: const StadiumBorder(),
        minimumSize: const Size(44, 44),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18), const SizedBox(width: 7),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    ),
  );
}

class BrandStoryBanner extends StatelessWidget {
  final VoidCallback? onTap;
  const BrandStoryBanner({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? [const Color(0xFF34304F), const Color(0xFF263650)]
              : [
                  const Color(0xFFFFEFF8),
                  const Color(0xFFEEE9FF),
                  const Color(0xFFE8F1FF),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'bllii · 热爱收藏夹',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  '收藏每一份心动\n和喜欢的故事更近一步',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.7,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 12),
                  BrandButton(
                    onPressed: onTap,
                    label: '我的追番',
                    icon: Icons.favorite_rounded,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const BrandLogo(width: 80, symbolOnly: true),
        ],
      ),
    );
  }
}

class BrandBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;
  const BrandBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const labels = ['首页', '发现', '排行', '更新', '我的'];
    const icons = [
      Icons.home_outlined,
      Icons.explore_outlined,
      Icons.star_outline_rounded,
      Icons.calendar_month_outlined,
      Icons.person_outline_rounded,
    ];
    const activeIcons = [
      Icons.home_rounded,
      Icons.explore_rounded,
      Icons.star_rounded,
      Icons.calendar_month_rounded,
      Icons.person_rounded,
    ];
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(
            color: dark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B7E94C5),
            blurRadius: 18,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(
              5,
              (index) => Expanded(
                child: Semantics(
                  selected: currentIndex == index,
                  button: true,
                  label: labels[index],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onSelected(index),
                    child: index == 2
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dark
                                    ? AppColors.darkBg
                                    : const Color(0xFFF9FAFF),
                                border: Border.all(
                                  color: currentIndex == index
                                      ? AppColors.purple
                                      : AppColors.lightBorder,
                                ),
                              ),
                              child: const BrandLogo(
                                width: 42,
                                symbolOnly: true,
                              ),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                currentIndex == index
                                    ? activeIcons[index]
                                    : icons[index],
                                size: 23,
                                color: currentIndex == index
                                    ? Theme.of(context).colorScheme.primary
                                    : AppColors.lightTextSecondary,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                labels[index],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: currentIndex == index
                                      ? Theme.of(context).colorScheme.primary
                                      : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
