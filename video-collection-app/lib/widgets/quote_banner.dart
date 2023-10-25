import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class QuoteBannerWidget extends StatelessWidget {
  const QuoteBannerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFFFEDF8), const Color(0xFFE9EDFF)],
        ),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.primary100,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary600.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.format_quote_rounded,
                size: 20,
                color: AppColors.primary500.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  '“ 有些相遇，一生都会记得。”',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '——《葬送的芙莉莲》· 欣梅尔',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
