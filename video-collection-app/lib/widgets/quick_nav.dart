import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class QuickNavWidget extends StatelessWidget {
  final Function(int targetTab) onNavTap;
  final VoidCallback onHistoryTap;
  const QuickNavWidget({
    super.key,
    required this.onNavTap,
    required this.onHistoryTap,
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      ('番剧', Icons.live_tv_rounded, AppColors.primary500, () => onNavTap(1)),
      ('新番', Icons.video_library_rounded, AppColors.rose, () => onNavTap(3)),
      ('排行榜', Icons.star_rounded, AppColors.primary500, () => onNavTap(2)),
      ('我的追番', Icons.favorite_rounded, AppColors.purple, () => onNavTap(4)),
      ('观看历史', Icons.history_rounded, AppColors.rose, onHistoryTap),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Row(
        children: items
            .map(
              (item) => Expanded(
                child: InkWell(
                  onTap: item.$4,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: item.$3.withValues(alpha: dark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(item.$2, size: 27, color: item.$3),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.$1,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
