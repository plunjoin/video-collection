import 'package:flutter/material.dart';

import '../models/video_model.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_controls.dart';
import '../widgets/brand_widgets.dart';
import '../utils/responsive.dart';
import '../widgets/anime_poster_card.dart';
import '../widgets/desktop_horizontal_scroll.dart';
import 'anime_detail_screen.dart';

class CategoryScreen extends StatefulWidget {
  final int? initialTypeId;

  const CategoryScreen({super.key, this.initialTypeId});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<Category> _categories = [];
  int _selectedTypeId = 4;
  String _selectedGenre = '全部';
  String _selectedYear = '全部';
  String _selectedSort = 'time';

  int _page = 1;
  int _loadGeneration = 0;
  final int _pageSize = 24;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  List<VideoRecord> _videos = [];

  final List<String> _genres = [
    '全部',
    '热血',
    '玄幻',
    '修真',
    '冒险',
    '奇幻',
    '科幻',
    '搞笑',
    '治愈',
    '恋爱',
    '悬疑',
  ];

  List<String> get _years => [
    '全部',
    for (
      var year = DateTime.now().year;
      year >= DateTime.now().year - 4;
      year--
    )
      year.toString(),
    '更早',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialTypeId != null) {
      _selectedTypeId = widget.initialTypeId!;
    }
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  String? get _requestYear =>
      _selectedYear == '全部' || _selectedYear == '更早' ? null : _selectedYear;

  List<VideoRecord> _applyLocalFilters(List<VideoRecord> videos) {
    return videos.where((video) {
      if (_selectedGenre != '全部' && !video.tags.contains(_selectedGenre)) {
        return false;
      }
      if (_selectedYear == '更早') {
        final year = int.tryParse(video.year);
        if (year == null || year >= DateTime.now().year - 4) return false;
      }
      return true;
    }).toList();
  }

  bool _hasAnotherPage(Map<String, dynamic> response, int page, int count) {
    final total = response['total'];
    if (total is int) return page * _pageSize < total;
    return count >= _pageSize;
  }

  Future<void> _loadInitial() async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _page = 1;
      _hasMore = false;
    });

    var cats = _categories;
    if (cats.isEmpty) cats = await _apiService.getCategories();
    if (widget.initialTypeId == null &&
        cats.isNotEmpty &&
        !cats.any((category) => category.id == _selectedTypeId)) {
      _selectedTypeId = cats.first.id;
    }
    final response = await _apiService.getVideos(
      page: 1,
      pageSize: _pageSize,
      typeId: _selectedTypeId,
      year: _requestYear,
      sort: _selectedSort,
    );
    final rawItems = (response['list'] as List<VideoRecord>?) ?? [];
    final items = _applyLocalFilters(rawItems);

    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _categories = cats;
      _videos = items;
      _isLoading = false;
      _hasMore = _hasAnotherPage(response, 1, rawItems.length);
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    final generation = _loadGeneration;
    final nextPage = _page + 1;
    setState(() => _isLoadingMore = true);

    final response = await _apiService.getVideos(
      page: nextPage,
      pageSize: _pageSize,
      typeId: _selectedTypeId,
      year: _requestYear,
      sort: _selectedSort,
    );
    final rawItems = (response['list'] as List<VideoRecord>?) ?? [];
    final items = _applyLocalFilters(rawItems);

    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _page = nextPage;
      _videos.addAll(items);
      _isLoadingMore = false;
      _hasMore = _hasAnotherPage(response, nextPage, rawItems.length);
    });
  }

  void _openDetail(VideoRecord video) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailScreen(videoId: video.id)),
    );
  }

  bool get _hasActiveFilter =>
      _selectedGenre != '全部' || _selectedYear != '全部' || _selectedSort != 'time';

  void _resetFilters() {
    setState(() {
      _selectedGenre = '全部';
      _selectedYear = '全部';
      _selectedSort = 'time';
    });
    _loadInitial();
  }

  /// 工具栏式筛选：分类是文字 tab，题材 / 年份 / 排序是安静的文本下拉，
  /// 宽屏一行排完，窄屏才换行。整条只有 48px 高。
  Widget _buildFilterBar(bool isDark) {
    final line = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final filters = <Widget>[
      _FilterButton<String>(
        label: '题材',
        value: _selectedGenre,
        defaultValue: '全部',
        options: [for (final genre in _genres) (genre, genre)],
        onSelected: (genre) {
          setState(() => _selectedGenre = genre);
          _loadInitial();
        },
      ),
      _FilterButton<String>(
        label: '年份',
        value: _selectedYear,
        defaultValue: '全部',
        options: [for (final year in _years) (year, year)],
        onSelected: (year) {
          setState(() => _selectedYear = year);
          _loadInitial();
        },
      ),
      _FilterButton<String>(
        label: '排序',
        value: _selectedSort,
        defaultValue: 'time',
        options: const [
          ('time', '最新更新'),
          ('hits', '人气热播'),
          ('score', '口碑精选'),
        ],
        onSelected: (sort) {
          setState(() => _selectedSort = sort);
          _loadInitial();
        },
      ),
      if (_hasActiveFilter) _TextAction(label: '重置', onTap: _resetFilters),
    ];

    final tabs = SizedBox(
      height: 48,
      child: _categories.isEmpty
          ? const SizedBox.shrink()
          : DesktopHorizontalScroll(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final category in _categories)
                      _CategoryTab(
                        label: category.name,
                        selected: category.id == _selectedTypeId,
                        onTap: () {
                          if (category.id == _selectedTypeId) return;
                          setState(() => _selectedTypeId = category.id);
                          _loadInitial();
                        },
                      ),
                  ],
                ),
              ),
            ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : Colors.white,
        border: Border(bottom: BorderSide(color: line, width: .8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 620) {
              return Row(
                children: [
                  Expanded(child: tabs),
                  const SizedBox(width: 12),
                  ...filters,
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tabs,
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: filters),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = Responsive.isDesktop(context);

    Widget content = Column(
      children: [
        // 顶部筛选工具栏（自带底部分隔线）
        _buildFilterBar(isDark),

        // 结果列表
        Expanded(
          child: _isLoading
              ? const Center(child: BrandLoading())
              : _videos.isEmpty
              ? BrandEmpty(
                  title: '还没有这样的故事',
                  subtitle: _hasMore
                      ? '这一页没有匹配结果，继续加载后续内容。'
                      : '换个题材或年份，说不定就遇见了。',
                  action: _hasMore
                      ? BrandButton(
                          label: '继续加载',
                          icon: Icons.expand_more_rounded,
                          onPressed: _isLoadingMore ? null : _loadMore,
                        )
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: _loadInitial,
                  color: AppColors.primary500,
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: Responsive.gridColumns(
                        context,
                        itemMinWidth: 140,
                        min: 3,
                        max: 6,
                      ),
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: _videos.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _videos.length) {
                        return Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkCard
                                : AppColors.lightBorder,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: _isLoadingMore
                                ? const BrandSpinner(size: 20)
                                : IconButton(
                                    tooltip: '加载更多',
                                    onPressed: _loadMore,
                                    icon: const Icon(
                                      Icons.expand_more_rounded,
                                      color: AppColors.primary500,
                                    ),
                                  ),
                          ),
                        );
                      }
                      final video = _videos[index];
                      return AnimePosterCard(
                        video: video,
                        onTap: () => _openDetail(video),
                      );
                    },
                  ),
                ),
        ),
      ],
    );

    if (isDesktop) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: content,
        ),
      );
    }

    return Scaffold(
      appBar: BrandAppBar(title: const Text('发现 · 分类')),
      body: content,
    );
  }
}

/// 分类文字 tab：选中时墨色加粗 + 底部一小段品牌粉下划线。
class _CategoryTab extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<_CategoryTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
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
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: widget.selected || _hovered ? ink : muted,
                  ),
                ),
                Positioned(
                  bottom: 7,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: widget.selected ? 18 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.rose,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 文本式下拉筛选：平时完全透明，悬停给一层淡底，选中后整枚染上主色。
class _FilterButton<T> extends StatefulWidget {
  final String label;
  final T value;
  final T defaultValue;
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;

  const _FilterButton({
    required this.label,
    required this.value,
    required this.defaultValue,
    required this.options,
    required this.onSelected,
  });

  @override
  State<_FilterButton<T>> createState() => _FilterButtonState<T>();
}

class _FilterButtonState<T> extends State<_FilterButton<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final active = widget.value != widget.defaultValue;
    final selectedLabel = widget.options
        .firstWhere(
          (option) => option.$1 == widget.value,
          orElse: () => widget.options.first,
        )
        .$2;

    return PopupMenuButton<T>(
      tooltip: '选择${widget.label}',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      onSelected: widget.onSelected,
      itemBuilder: (context) => [
        for (final option in widget.options)
          PopupMenuItem<T>(
            value: option.$1,
            height: 38,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.$2,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: option.$1 == widget.value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: option.$1 == widget.value ? primary : null,
                    ),
                  ),
                ),
                if (option.$1 == widget.value)
                  Icon(Icons.check_rounded, size: 15, color: primary),
              ],
            ),
          ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? primary.withValues(alpha: dark ? .18 : .08)
                : (_hovered
                      ? (dark
                            ? const Color(0xFF222E43)
                            : const Color(0xFFF4F7FF))
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(fontSize: 11, height: 1, color: muted),
              ),
              const SizedBox(width: 5),
              Text(
                selectedLabel,
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: active ? primary : ink,
                ),
              ),
              const SizedBox(width: 1),
              Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: active ? primary : muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TextAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: dark
            ? AppColors.darkTextSecondary
            : AppColors.lightTextSecondary,
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text(label),
    );
  }
}
