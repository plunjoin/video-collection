import 'package:flutter/material.dart';
import '../widgets/brand_controls.dart';

import '../models/video_model.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_widgets.dart';
import '../utils/responsive.dart';
import '../widgets/anime_poster_card.dart';
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

  final List<String> _years = [
    '全部',
    '2025',
    '2024',
    '2023',
    '2022',
    '2021',
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

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _page = 1;
      _hasMore = true;
    });

    final cats = await _apiService.getCategories();
    final res = await _apiService.getVideos(
      page: _page,
      pageSize: _pageSize,
      typeId: _selectedTypeId,
      year: _selectedYear,
      sort: _selectedSort,
    );

    List<VideoRecord> list = (res['list'] as List<VideoRecord>?) ?? [];
    if (_selectedGenre != '全部') {
      list = list.where((v) => v.tags.contains(_selectedGenre)).toList();
    }

    if (!mounted) return;
    setState(() {
      _categories = cats;
      _videos = list;
      _isLoading = false;
      _hasMore = list.length >= _pageSize;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
    });

    final nextPage = _page + 1;
    final res = await _apiService.getVideos(
      page: nextPage,
      pageSize: _pageSize,
      typeId: _selectedTypeId,
      year: _selectedYear,
      sort: _selectedSort,
    );

    List<VideoRecord> list = (res['list'] as List<VideoRecord>?) ?? [];
    if (_selectedGenre != '全部') {
      list = list.where((v) => v.tags.contains(_selectedGenre)).toList();
    }

    if (!mounted) return;
    setState(() {
      _page = nextPage;
      _videos.addAll(list);
      _isLoadingMore = false;
      _hasMore = list.length >= _pageSize;
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: items.map((item) {
          final isSelected = item == selectedItem;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: BrandPill(label: Text(labelBuilder(item)),selected: isSelected,onSelected: (_) => onSelected(item)),
          );
        }).toList(),
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
          IconButton(icon: const Icon(Icons.tune_rounded), tooltip: '排序方式', onPressed: () async {
            final sort = await showBrandOptions<String>(context, title: '按喜欢的方式发现',
              selected: _selectedSort, options: [('time','最新更新'),('hits','人气热播'),('score','口碑精选')]);
            if (sort != null && mounted) { setState(() => _selectedSort = sort); _loadInitial(); }
          }),
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
                ? const BrandEmpty(title: '还没有这样的故事', subtitle: '换个题材或年份，说不定就遇见了。')
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
                      itemCount: _videos.length + (_isLoadingMore ? 3 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _videos.length) {
                          return Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkCard
                                  : AppColors.lightBorder,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.primary500,
                                  ),
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
