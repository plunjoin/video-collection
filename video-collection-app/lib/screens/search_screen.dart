import 'package:flutter/material.dart';
import '../widgets/brand_controls.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_widgets.dart';
import '../utils/responsive.dart';
import '../widgets/anime_poster_card.dart';
import '../widgets/search_bar_widget.dart';
import 'anime_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? initialKeyword;

  const SearchScreen({super.key, this.initialKeyword});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final ApiService _apiService = ApiService();

  bool _isSearching = false;
  bool _hasSearched = false;
  List<VideoRecord> _searchResults = [];

  final List<String> _hotKeywords = [
    '葬送的芙莉莲',
    '斗破苍穹',
    '凡人修仙传',
    '间谍过家家',
    '鬼灭之刃',
    '沧元图',
    '异世界',
    '修仙',
    '热血战斗',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      _controller.text = widget.initialKeyword!;
      _performSearch(widget.initialKeyword!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    Provider.of<AppStateProvider>(
      context,
      listen: false,
    ).addSearchKeyword(query);

    final res = await _apiService.getVideos(keyword: query, pageSize: 50);
    final list = (res['list'] as List<VideoRecord>?) ?? [];

    if (!mounted) return;
    setState(() {
      _searchResults = list;
      _isSearching = false;
    });
  }

  void _openDetail(VideoRecord video) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailScreen(videoId: video.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: BrandAppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: SearchBarWidget(
            controller: _controller,
            readOnly: false,
            autoFocus: widget.initialKeyword == null,
            onTap: () {},
            onSubmitted: _performSearch,
          ),
        ),
      ),
      body: _isSearching
          ? const Center(child: BrandLoading())
          : _hasSearched
          ? _buildSearchResults(isDark)
          : _buildHistoryAndHot(isDark),
    );
  }

  Widget _buildSearchResults(bool isDark) {
    if (_searchResults.isEmpty) {
      return BrandEmpty(title: '还没有找到这个故事',
        subtitle: '试试更短的名字，或者换一个关键词。',
        action: BrandButton(label: '重新寻找', icon: Icons.search_rounded,
          onPressed: () => setState(() { _hasSearched = false; _controller.clear(); })));

    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '搜索结果 (${_searchResults.length}部)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
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
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final video = _searchResults[index];
              return AnimePosterCard(
                video: video,
                onTap: () => _openDetail(video),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryAndHot(bool isDark) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        final history = appState.searchHistory;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandPageBanner(title: '寻找心动的故事', subtitle: '记得一个名字，就能再次相遇。', eyebrow: 'FIND YOUR NEXT STORY'),
              // 搜索历史
              if (history.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '搜索历史',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      tooltip: '清空历史',
                      onPressed: () => appState.clearSearchHistory(),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: history.map((item) {
                    return BrandPill(label: Text(item),onPressed: () {
                        _controller.text = item;
                        _performSearch(item);
                      });
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // 热门推荐
              Text(
                '大家都在搜',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _hotKeywords.map((item) {
                  return BrandPill(label: Text(item),onPressed: () {
                      _controller.text = item;
                      _performSearch(item);
                    });
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
