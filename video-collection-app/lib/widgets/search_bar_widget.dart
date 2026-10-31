import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/brand_icons.dart';

class SearchBarWidget extends StatelessWidget {
  final VoidCallback onTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final bool autoFocus;

  const SearchBarWidget({
    super.key,
    required this.onTap,
    this.controller,
    this.onSubmitted,
    this.onChanged,
    this.readOnly = true,
    this.autoFocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
            const BrandIcon(
              BIcons.search,
              size: 18,
              color: AppColors.primary500,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: readOnly
                  ? Text(
                      '搜索番剧、资讯…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    )
                  : TextField(
                      controller: controller,
                      autofocus: autoFocus,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入番剧名称、题材关键词...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                    ),
            ),
            if (!readOnly && controller != null)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller!,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () {
                      controller!.clear();
                      onChanged?.call('');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: BrandIcon(
                        BIcons.cancel,
                        size: 16,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
