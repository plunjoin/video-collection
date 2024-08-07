import 'package:flutter/material.dart';

import '../widgets/brand_controls.dart';

import '../models/video_model.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
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

  Widget _buildFilterChipRow<T>({
    required List<T> items,
    required T selectedItem,
    required String Function(T) labelBuilder,
    required Function(T) onSelected,
  }) {
    return DesktopHorizontalScroll(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: items.map((item) {
            final isSelected = item == selectedItem;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: BrandPill(
                label: Text(labelBuilder(item)),
                selected: isSelected,
                onSelected: (_) => onSelected(item),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: BrandAppBar(
        title: const Text('发现  ·  分类'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: '排序方式',
            onPressed: () async {
              final sort = await showBrandOptions<String>(
                context,
                title: '按喜欢的方式发现',
                selected: _selectedSort,
                options: [
                  ('time', '最新更新'),
                  ('hits', '人气热播'),
                  ('score', '口碑精选'),
                ],
              );
              if (sort != null && mounted) {
                setState(() => _selectedSort = sort);
                _loadInitial();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部筛选条件区域
          Container(
            color: isDark ? AppColors.darkBg : AppColors.lightBg,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 分类类型
                if (_categories.isNotEmpty)
                  _buildFilterChipRow<Category>(
                    items: _categories,
                    selectedItem: _categories.firstWhere(
                      (c) => c.id == _selectedTypeId,
                      orElse: () => _categories.first,
                    ),
                    labelBuilder: (c) => c.name,
                    onSelected: (c) {
                      setState(() {
                        _selectedTypeId = c.id;
                      });
                      _loadInitial();
                    },
                  ),
                const SizedBox(height: 6),

                // 2. 题材
                _buildFilterChipRow<String>(
                  items: _genres,
                  selectedItem: _selectedGenre,
                  labelBuilder: (g) => g,
                  onSelected: (g) {
                    setState(() {
                      _selectedGenre = g;
                    });
                    _loadInitial();
                  },
                ),
                const SizedBox(height: 6),

                // 3. 年份
                _buildFilterChipRow<String>(
                  items: _years,
                  selectedItem: _selectedYear,
                  labelBuilder: (y) => y,
                  onSelected: (y) {
                    setState(() {
                      _selectedYear = y;
                    });
                    _loadInitial();
                  },
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),

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
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: Responsive.gridColumns(
                          context,
                          itemMinWidth: 130,
                          min: 3,
                          max: 8,
                        ),
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 12,
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
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              AppColors.primary500,
                                            ),
                                      ),
                                    )
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
      ),
    );
  }
}
