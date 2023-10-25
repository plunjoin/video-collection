import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SearchBarWidget extends StatelessWidget {
  final VoidCallback onTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;
  final bool autoFocus;

  const SearchBarWidget({
    super.key,
    required this.onTap,
    this.controller,
    this.onSubmitted,
    this.readOnly = true,
    this.autoFocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : AppColors.primary50,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 16,
              color: AppColors.primary500,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: readOnly
                  ? Text(
                      '搜索番剧、视频…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    )
                  : TextField(
                      controller: controller,
                      autofocus: autoFocus,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入番剧名称、题材关键词...',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: onSubmitted,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
