import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/video_model.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import 'brand_widgets.dart';
import 'episode_selector.dart';

class AnimePosterCard extends StatefulWidget {
  final VideoRecord video;
  final VoidCallback onTap;
  final double? width;
  final double? height;

  const AnimePosterCard({
    super.key,
    required this.video,
    required this.onTap,
    this.width,
    this.height,
  });

  @override
  State<AnimePosterCard> createState() => _AnimePosterCardState();
}

class _AnimePosterCardState extends State<AnimePosterCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext buildContext) {
    final isDark = Theme.of(buildContext).brightness == Brightness.dark;
    final isDesktop = !kIsWeb && Responsive.isDesktopPlatform;

    return MouseRegion(
      onEnter: (_) => isDesktop ? setState(() => _isHovered = true) : null,
      onExit: (_) => isDesktop ? setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 海报主体
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(
                    0,
                    _isHovered ? -3.5 : 0,
                    0,
                  ),
                  child: Stack(
                    children: [
                      // 图片与圆角剪裁
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isDark
                              ? AppColors.darkCard
                              : AppColors.lightBorder,
                          border: Border.all(
                            color: _isHovered
                                ? AppColors.purple.withValues(
                                    alpha: isDark ? 0.65 : 0.5,
                                  )
                                : (isDark
                                    ? AppColors.darkBorder.withValues(
                                        alpha: 0.6,
                                      )
                                    : AppColors.lightBorder),
                            width: _isHovered ? 1.2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _isHovered
                                  ? AppColors.purple.withValues(
                                      alpha: isDark ? 0.25 : 0.15,
                                    )
                                  : AppColors.primary500.withValues(
                                      alpha: 0.03,
                                    ),
                              blurRadius: _isHovered ? 16 : 8,
                              offset: Offset(0, _isHovered ? 6 : 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CachedNetworkImage(
                          imageUrl: widget.video.picture,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Stack(
                            fit: StackFit.expand,
                            children: [
                              BrandPosterFallback(title: widget.video.name),
                              const Center(child: BrandSpinner(size: 18)),
                            ],
                          ),
                          errorWidget: (context, url, error) =>
                              BrandPosterFallback(title: widget.video.name),
                        ),
                      ),

                      // 顶部角标 (更新至X集 / 完结)
                      if (widget.video.remarks.isNotEmpty)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: widget.video.remarks.contains('完')
                                  ? AppColors.emerald.withValues(alpha: 0.9)
                                  : AppColors.rose.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              widget.video.remarks,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // 片名
              Text(
                widget.video.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),

              const SizedBox(height: 2),

              // 题材标签
              Text(
                widget.video.tags.take(2).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情页和播放页底部的横滑推荐海报。
class AudiencePosterTile extends StatelessWidget {
  final VideoRecord video;
  final VoidCallback onTap;
  final double width;

  const AudiencePosterTile({
    super.key,
    required this.video,
    required this.onTap,
    this.width = 108,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: width,
                height: width * 1.28,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (video.picture.isEmpty)
                      BrandPosterFallback(title: video.name)
                    else
                      CachedNetworkImage(
                        imageUrl: video.picture,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            BrandPosterFallback(title: video.name),
                        placeholder: (_, _) =>
                            BrandPosterFallback(title: video.name),
                      ),
                    if (video.hits > 0)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Text(
                          formatAudienceCount(video.hits),
                          style: const TextStyle(
                            color: Color(0xFFFFB020),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              video.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            Text(
              video.hits > 0
                  ? '${formatAudienceCount(video.hits)} 播放'
                  : (video.remarks.isEmpty ? video.typeName : video.remarks),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
