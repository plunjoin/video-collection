import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/video_model.dart';
import '../theme/app_colors.dart';
import 'brand_widgets.dart';

class HeroBannerWidget extends StatefulWidget {
  final List<VideoRecord> banners;
  final Function(VideoRecord) onPlayTap;
  final Function(VideoRecord) onDetailTap;
  const HeroBannerWidget({
    super.key,
    required this.banners,
    required this.onPlayTap,
    required this.onDetailTap,
  });
  @override
  State<HeroBannerWidget> createState() => _HeroBannerWidgetState();
}

class _HeroBannerWidgetState extends State<HeroBannerWidget> {
  final _controller = PageController();
  int _current = 0;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 260 : 330,
          child: Stack(
            children: [
              if (banners.isEmpty)
                Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.brandGradient,
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BrandLogo(width: 86, symbolOnly: true),
                        SizedBox(height: 18),
                        Text(
                          '在更多的故事里，遇见更好的你',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              if (banners.isNotEmpty)
                PageView.builder(
                  controller: _controller,
                  itemCount: banners.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, i) {
                    final video = banners[i];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: video.picture,
                          fit: BoxFit.cover,
                          alignment: const Alignment(0.35, -0.45),
                          placeholder: (_, url) =>
                              const ColoredBox(color: Color(0xFFABBFEB)),
                          errorWidget: (_, url, error) => const ColoredBox(
                            color: Color(0xFFABBFEB),
                            child: Center(
                              child: BrandLogo(width: 110, symbolOnly: true),
                            ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xB8677BB1), Color(0x307D93C7)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 23,
                          right: 24,
                          top: 26,
                          bottom: 26,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MORE STORIES, TOGETHER',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '在更多的故事里\n遇见更好的你',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                  letterSpacing: 1,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => widget.onDetailTap(video),
                                child: Text(
                                  video.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 9),
                              BrandButton(
                                onPressed: () => widget.onPlayTap(video),
                                label: '立即观看',
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              if (banners.length > 1)
                Positioned(
                  right: 14,
                  bottom: 9,
                  child: Row(
                    children: List.generate(banners.length, (i) {
                      return Semantics(
                        label: '第 ${i + 1} 张推荐',
                        selected: _current == i,
                        button: true,
                        child: GestureDetector(
                          onTap: () => _controller.animateToPage(
                            i,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                          child: SizedBox(
                            width: 22,
                            height: 24,
                            child: Center(
                              child: Container(
                                width: i == _current ? 16 : 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(
                                    alpha: i == _current ? 1 : 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
