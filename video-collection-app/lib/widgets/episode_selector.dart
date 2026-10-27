import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/video_model.dart';
import '../theme/app_colors.dart';
import 'brand_controls.dart';
import 'brand_widgets.dart';
import 'desktop_horizontal_scroll.dart';

/// 把播放量收成「1.2万」这种短数字，详情和播放页共用。
String formatAudienceCount(int count) {
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
  if (count >= 10000) {
    final value = count / 10000;
    final text = value >= 10
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text万';
  }
  return '$count';
}

/// 选集超过 99 集时按 1-99、100-198 这样分页。
const int episodeRangeSize = 99;

/// 单页超过这个数量时先折叠，避免几百集把详情页撑满。
const int episodeCollapseCount = 30;

class EpisodeRange {
  final int start;
  final int end;
  const EpisodeRange(this.start, this.end);

  String get label {
    final from = start + 1;
    final to = end;
    return from == to ? '$from' : '$from-$to';
  }
}

List<EpisodeRange> episodeRanges(int count, {int size = episodeRangeSize}) {
  if (count <= 0 || size <= 0) return const [];
  final ranges = <EpisodeRange>[];
  for (var start = 0; start < count; start += size) {
    ranges.add(EpisodeRange(start, (start + size).clamp(0, count)));
  }
  return ranges;
}

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
  int _rangeIndex = 0;
  bool _expanded = false;
  int? _syncedEpisode;

  @override
  void initState() {
    super.initState();
    _selectedGroupIndex = widget.currentGroupIndex;
    _syncPlayingRange(force: true);
  }

  @override
  void didUpdateWidget(covariant EpisodeSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentGroupIndex != oldWidget.currentGroupIndex) {
      _selectedGroupIndex = widget.currentGroupIndex;
      _expanded = false;
    }
    _syncPlayingRange();
  }

  void _syncPlayingRange({bool force = false}) {
    if (widget.playGroups.isEmpty) return;
    if (_selectedGroupIndex != widget.currentGroupIndex) return;
    if (!force && _syncedEpisode == widget.currentEpisodeIndex) return;
    _syncedEpisode = widget.currentEpisodeIndex;
    final count = widget.playGroups[_selectedGroupIndex].episodes.length;
    if (count == 0) return;
    final ranges = episodeRanges(count);
    _rangeIndex = (widget.currentEpisodeIndex ~/ episodeRangeSize).clamp(
      0,
      ranges.length - 1,
    );
    final offset = widget.currentEpisodeIndex - _rangeIndex * episodeRangeSize;
    if (offset >= episodeCollapseCount) _expanded = true;
  }

  void _selectGroup(int index) {
    setState(() {
      _selectedGroupIndex = index;
      _expanded = false;
      if (index == widget.currentGroupIndex) {
        _syncedEpisode = null;
        _syncPlayingRange(force: true);
      } else {
        _rangeIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

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
    final ranges = episodeRanges(originalEpisodes.length);
    final safeRange = ranges.isEmpty
        ? 0
        : _rangeIndex.clamp(0, ranges.length - 1);
    final range = ranges.isEmpty ? const EpisodeRange(0, 0) : ranges[safeRange];
    final rangedIndices = [
      for (var index = range.start; index < range.end; index++) index,
    ];
    final orderedIndices = _isAscending
        ? rangedIndices
        : rangedIndices.reversed.toList();
    final collapsed =
        !_expanded && orderedIndices.length > episodeCollapseCount;
    final visibleIndices = collapsed
        ? orderedIndices.take(episodeCollapseCount).toList()
        : orderedIndices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部：线路切换 · 集数 · 排序
        Row(
          children: [
            Expanded(
              child: DesktopHorizontalScroll(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(widget.playGroups.length, (index) {
                      final group = widget.playGroups[index];
                      final label = group.server.isNotEmpty
                          ? group.server
                          : '播放源 ${index + 1}';
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _SourcePill(
                          label: label,
                          selected: _selectedGroupIndex == index,
                          onTap: () => _selectGroup(index),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '共 ${originalEpisodes.length} 话',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            const SizedBox(width: 2),
            _SortToggle(
              ascending: _isAscending,
              onTap: () => setState(() => _isAscending = !_isAscending),
            ),
          ],
        ),

        if (ranges.length > 1) ...[
          const SizedBox(height: 8),
          DesktopHorizontalScroll(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(ranges.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _SourcePill(
                      label: ranges[index].label,
                      selected: safeRange == index,
                      onTap: () {
                        if (safeRange == index) return;
                        setState(() {
                          _rangeIndex = index;
                          _expanded = false;
                        });
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),

        // 剧集矩阵：只留序号，密而有序
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            const cell = 44.0;
            final columns = ((constraints.maxWidth + gap) / (cell + gap))
                .floor()
                .clamp(4, 14);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: cell,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
              ),
              itemCount: visibleIndices.length,
              itemBuilder: (context, idx) {
                final actualIdx = visibleIndices[idx];
                final episode = originalEpisodes[actualIdx];
                return _EpisodeCell(
                  number: episodeNumberLabel(episode.name, actualIdx),
                  title: episode.name,
                  playing:
                      _selectedGroupIndex == widget.currentGroupIndex &&
                      actualIdx == widget.currentEpisodeIndex,
                  onTap: () =>
                      widget.onSelected(_selectedGroupIndex, actualIdx),
                );
              },
            );
          },
        ),
        if (collapsed ||
            (_expanded && orderedIndices.length > episodeCollapseCount))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              label: Text(
                _expanded
                    ? '收起选集'
                    : '展开剩余 ${orderedIndices.length - visibleIndices.length} 集',
              ),
            ),
          ),
      ],
    );
  }
}

/// 播放页选集。只保留剧集卡片，不再同时铺一排编号按钮。
class EpisodeCardList extends StatefulWidget {
  final List<PlayGroup> playGroups;
  final int currentGroupIndex;
  final int currentEpisodeIndex;
  final String posterUrl;
  final void Function(int groupIndex, int episodeIndex) onSelected;

  const EpisodeCardList({
    super.key,
    required this.playGroups,
    required this.currentGroupIndex,
    required this.currentEpisodeIndex,
    required this.onSelected,
    this.posterUrl = '',
  });

  @override
  State<EpisodeCardList> createState() => _EpisodeCardListState();
}

class _EpisodeCardListState extends State<EpisodeCardList> {
  static const _previewCount = 4;
  late int _selectedGroupIndex;
  bool _expanded = false;
  int _rangeIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedGroupIndex = widget.currentGroupIndex;
  }

  @override
  void didUpdateWidget(covariant EpisodeCardList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentGroupIndex != oldWidget.currentGroupIndex) {
      _selectedGroupIndex = widget.currentGroupIndex;
      _expanded = false;
      _rangeIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (widget.playGroups.isEmpty) {
      return const Text('暂无可播放片源');
    }
    final groupIndex = _selectedGroupIndex.clamp(
      0,
      widget.playGroups.length - 1,
    );
    final episodes = widget.playGroups[groupIndex].episodes;
    final ranges = episodeRanges(episodes.length, size: 30);
    final safeRange = ranges.isEmpty
        ? 0
        : _rangeIndex.clamp(0, ranges.length - 1);
    final indexes = _visibleIndexes(episodes.length, ranges, safeRange);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.playGroups.length > 1)
          DesktopHorizontalScroll(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < widget.playGroups.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BrandPill(
                        label: Text(
                          widget.playGroups[index].server.isEmpty
                              ? '播放源 ${index + 1}'
                              : widget.playGroups[index].server,
                        ),
                        selected: groupIndex == index,
                        onSelected: (selected) {
                          if (!selected) return;
                          setState(() {
                            _selectedGroupIndex = index;
                            _expanded = false;
                            _rangeIndex = 0;
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_expanded && ranges.length > 1) ...[
          const SizedBox(height: 8),
          DesktopHorizontalScroll(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < ranges.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BrandPill(
                        label: Text(ranges[index].label),
                        selected: safeRange == index,
                        onSelected: (selected) {
                          if (!selected) return;
                          setState(() => _rangeIndex = index);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final index in indexes)
          _card(
            episodes[index],
            index,
            dark,
            playing:
                groupIndex == widget.currentGroupIndex &&
                index == widget.currentEpisodeIndex,
          ),
        if (episodes.length > _previewCount)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起选集' : '展开全部 ${episodes.length} 话'),
            ),
          ),
      ],
    );
  }

  List<int> _visibleIndexes(
    int count,
    List<EpisodeRange> ranges,
    int safeRange,
  ) {
    if (count == 0) return const [];
    if (_expanded && ranges.length > 1) {
      final range = ranges[safeRange];
      return [for (var index = range.start; index < range.end; index++) index];
    }
    if (_expanded || count <= _previewCount) {
      return [for (var index = 0; index < count; index++) index];
    }
    var start = _selectedGroupIndex == widget.currentGroupIndex
        ? widget.currentEpisodeIndex
        : 0;
    if (start + _previewCount > count) start = count - _previewCount;
    if (start < 0) start = 0;
    return [
      for (
        var index = start;
        index < start + _previewCount && index < count;
        index++
      )
        index,
    ];
  }

  Widget _card(Episode episode, int index, bool dark, {required bool playing}) {
    final border = dark ? AppColors.darkBorder : const Color(0xFFEEF1F6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: playing
            ? (dark
                  ? AppColors.rose.withValues(alpha: .16)
                  : const Color(0xFFFFF1F6))
            : (dark ? AppColors.darkCard : Colors.white),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onSelected(_selectedGroupIndex, index),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: playing ? AppColors.rose.withValues(alpha: .55) : border,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 112,
                    height: 64,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _thumb(dark),
                        if (playing) const ColoredBox(color: Color(0x33000000)),
                        if (playing)
                          const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (playing)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 2),
                          child: Text(
                            '正在播放',
                            style: TextStyle(
                              color: AppColors.rose,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Text(
                        episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: playing
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: dark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(bool dark) {
    final fallback = BrandPosterFallback(
      title: widget.posterUrl,
      showGlyph: false,
    );
    if (widget.posterUrl.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: widget.posterUrl,
      fit: BoxFit.cover,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}

/// 从剧集名里取出序号：优先用名字里的数字，取不到就用下标。
String episodeNumberLabel(String name, int index) {
  final matches = RegExp(r'\d+').allMatches(name);
  if (matches.isEmpty) return '${index + 1}';
  return matches.last.group(0)!;
}

/// 播放源 / 分页：安静的胶囊，选中才染色。
class _SourcePill extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SourcePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SourcePill> createState() => _SourcePillState();
}

class _SourcePillState extends State<_SourcePill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? primary.withValues(alpha: dark ? .20 : .09)
                : (_hovered
                      ? (dark
                            ? const Color(0xFF222E43)
                            : const Color(0xFFF4F7FF))
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: widget.selected
                  ? primary.withValues(alpha: .32)
                  : (dark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              color: widget.selected ? primary : muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SortToggle extends StatefulWidget {
  final bool ascending;
  final VoidCallback onTap;

  const _SortToggle({required this.ascending, required this.onTap});

  @override
  State<_SortToggle> createState() => _SortToggleState();
}

class _SortToggleState extends State<_SortToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: _hovered
                ? (dark ? const Color(0xFF222E43) : const Color(0xFFF4F7FF))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                widget.ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 13,
                color: muted,
              ),
              const SizedBox(width: 3),
              Text(
                widget.ascending ? '正序' : '倒序',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 剧集序号格：44×44 的软底方块，正在播放时整块染上品牌渐变。
class _EpisodeCell extends StatefulWidget {
  final String number;
  final String title;
  final bool playing;
  final VoidCallback onTap;

  const _EpisodeCell({
    required this.number,
    required this.title,
    required this.playing,
    required this.onTap,
  });

  @override
  State<_EpisodeCell> createState() => _EpisodeCellState();
}

class _EpisodeCellState extends State<_EpisodeCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Tooltip(
      message: widget.title,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: widget.playing
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF8BC4), Color(0xFF9A83FF)],
                    )
                  : null,
              color: widget.playing
                  ? null
                  : (_hovered
                        ? (dark
                              ? const Color(0xFF2A3852)
                              : const Color(0xFFE8EFFF))
                        : (dark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF6F8FD))),
              borderRadius: BorderRadius.circular(12),
              boxShadow: widget.playing
                  ? [
                      BoxShadow(
                        color: AppColors.rose.withValues(alpha: .30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              widget.number,
              style: TextStyle(
                fontSize: 13,
                height: 1,
                fontWeight: widget.playing ? FontWeight.w800 : FontWeight.w600,
                color: widget.playing ? Colors.white : ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
