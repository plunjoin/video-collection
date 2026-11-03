import '../ui/kit.dart';

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
    final muted = isDark ? AppColors.darkTextSecondary : AppColors.muted;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final border = isDark ? AppColors.darkBorder : AppColors.line;
    final bg = isDark ? AppColors.darkCard : const Color(0xFFF1F5F9);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            BrandIcon(
              BIcons.search,
              size: 16,
              color: muted,
              monochrome: true,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: readOnly
                  ? Text(
                      '搜索番剧、资讯…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: muted,
                      ),
                    )
                  : TextField(
                      controller: controller,
                      autofocus: autoFocus,
                      style: TextStyle(
                        fontSize: 13,
                        color: ink,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入番剧名称、题材关键词...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: muted,
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
                        color: muted,
                        monochrome: true,
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
