import 'package:flutter/material.dart';

import '../models/video_model.dart';
import '../theme/app_colors.dart';
import 'brand_controls.dart';

class EpisodeSelectorWidget extends StatefulWidget {
  final List<PlayGroup> playGroups;
  final int currentGroupIndex;
  final int currentEpisodeIndex;
  final Function(int groupIndex, int episodeIndex) onSelected;

  const EpisodeSelectorWidget({
    super.key,
    required this.playGroups,
    required this.currentGroupIndex,
    required this.currentEpisodeIndex,
    required this.onSelected,
  });

  @override
  State<EpisodeSelectorWidget> createState() => _EpisodeSelectorWidgetState();
}

class _EpisodeSelectorWidgetState extends State<EpisodeSelectorWidget> {
  late int _selectedGroupIndex;
  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _selectedGroupIndex = widget.currentGroupIndex;
  }

  @override
  void didUpdateWidget(covariant EpisodeSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentGroupIndex != oldWidget.currentGroupIndex) {
      _selectedGroupIndex = widget.currentGroupIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.playGroups.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            '暂无播放源',
            style: TextStyle(color: AppColors.darkTextSecondary),
          ),
        ),
      );
    }

    final currentGroup = widget.playGroups[_selectedGroupIndex];
    final originalEpisodes = currentGroup.episodes;
    final displayEpisodes = _isAscending
        ? originalEpisodes
        : originalEpisodes.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部：线路切换与排序
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 播放源切换 Chips
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(widget.playGroups.length, (index) {
                    final group = widget.playGroups[index];
                    final isSelected = _selectedGroupIndex == index;
                    final label = group.server.isNotEmpty
                        ? group.server
                        : '播放源 ${index + 1}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BrandPill(label: Text(label),selected: isSelected,onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedGroupIndex = index;
                            });
                          }
                        }),
                    );
                  }),
                ),
              ),
            ),

            // 排序按钮 (正序 / 倒序)
            InkWell(
              onTap: () {
                setState(() {
                  _isAscending = !_isAscending;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _isAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 14,
                      color: AppColors.primary500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isAscending ? '正序' : '倒序',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 剧集网格
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 2.2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: displayEpisodes.length,
          itemBuilder: (context, idx) {
            final episode = displayEpisodes[idx];
            final actualIdx = _isAscending
                ? idx
                : (originalEpisodes.length - 1 - idx);
            final isPlaying =
                _selectedGroupIndex == widget.currentGroupIndex &&
                actualIdx == widget.currentEpisodeIndex;

            return InkWell(
              onTap: () {
                widget.onSelected(_selectedGroupIndex, actualIdx);
              },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? (isDark
                            ? AppColors.purple.withValues(alpha: 0.15)
                            : const Color(0xFFFFF5FC))
                      : (isDark ? AppColors.darkCard : AppColors.primary50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPlaying
                        ? AppColors.rose
                        : (isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder),
                    width: isPlaying ? 1.5 : 1,
                  ),
                  boxShadow: isPlaying
                      ? [
                          BoxShadow(
                            color: AppColors.rose.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isPlaying) ...[
                      const Icon(
                        Icons.bar_chart_rounded,
                        size: 16,
                        color: AppColors.rose,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        episode.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isPlaying
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isPlaying
                              ? AppColors.rose
                              : (isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
