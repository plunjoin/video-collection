import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/brand_controls.dart';

import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/analytics_tracker.dart';
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
  final ScrollController _resultsScrollController = ScrollController();
  final ApiService _apiService = ApiService();

  Timer? _suggestionDebounce;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _isLoadingSuggestions = false;
  bool _hasSearched = false;
  bool _suggestionsAreHot = true;
  bool _hasMore = false;
  int _searchRequestId = 0;
  int _suggestionRequestId = 0;
  int _page = 1;
  final int _pageSize = 24;
  int _total = 0;
  List<String> _suggestions = [];
  List<VideoRecord> _searchResults = [];

  @override
  void initState() {
    super.initState();
    AnalyticsTracker().screen('search');
    _resultsScrollController.addListener(_onResultsScroll);
    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      _controller.text = widget.initialKeyword!;
      _performSearch(widget.initialKeyword!);
    } else {
      _loadSuggestions('');
    }
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _controller.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _suggestionDebounce?.cancel();
    _searchRequestId++;
    setState(() {
      _isSearching = false;
      _hasSearched = false;
      _isLoadingMore = false;
      _searchResults = [];
      _hasMore = false;
    });
    _suggestionDebounce = Timer(
      const Duration(milliseconds: 280),
      () => _loadSuggestions(value.trim()),
    );
  }

  Future<void> _loadSuggestions(String keyword) async {
    final requestId = ++_suggestionRequestId;
    if (mounted) setState(() => _isLoadingSuggestions = true);
    final result = await _apiService.getSearchSuggestions(keyword: keyword);
    if (!mounted || requestId != _suggestionRequestId) return;
    setState(() {
      _suggestions = List<String>.from(result['suggestions'] as List? ?? []);
      _suggestionsAreHot = result['hot'] == true;
      _isLoadingSuggestions = false;
    });
  }

  Future<void> _performSearch(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return;

    AnalyticsTracker().event('search', page: 'app://search', keyword: query);
    _suggestionDebounce?.cancel();
    final requestId = ++_searchRequestId;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _isLoadingMore = false;
      _hasSearched = true;
      _page = 1;
      _total = 0;
      _hasMore = false;
      _searchResults = [];
    });

    Provider.of<AppStateProvider>(
      context,
      listen: false,
    ).addSearchKeyword(query);

    final res = await _apiService.getVideos(
      keyword: query,
      page: 1,
      pageSize: _pageSize,
    );
    final list = (res['list'] as List<VideoRecord>?) ?? [];
    final total = res['total'] is int ? res['total'] as int : list.length;

    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _searchResults = list;
      _total = total;
      _hasMore = total > list.length;
      _isSearching = false;
    });
  }

  void _onResultsScroll() {
    if (!_resultsScrollController.hasClients ||
        _isSearching ||
        _isLoadingMore ||
        !_hasMore ||
        _resultsScrollController.position.extentAfter > 320) {
      return;
    }
    _loadMoreResults();
  }

  Future<void> _loadMoreResults() async {
    if (_isLoadingMore || !_hasMore) return;
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final requestId = _searchRequestId;
    final nextPage = _page + 1;
    setState(() => _isLoadingMore = true);
    final res = await _apiService.getVideos(
      keyword: query,
      page: nextPage,
      pageSize: _pageSize,
    );
    final nextItems = (res['list'] as List<VideoRecord>?) ?? [];
    if (!mounted || requestId != _searchRequestId) return;
    final existingIds = _searchResults.map((item) => item.id).toSet();
    final newItems = nextItems
        .where((item) => existingIds.add(item.id))
        .toList();
    setState(() {
      _page = nextPage;
      _searchResults.addAll(newItems);
      _hasMore = _searchResults.length < _total && nextItems.isNotEmpty;
      _isLoadingMore = false;
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
    final isDesktop = Responsive.isDesktop(context);

    final Widget body = _isSearching
        ? const Center(child: BrandLoading())
        : _hasSearched
        ? _buildSearchResults(isDark)
        : _buildHistoryAndHot(isDark);

    return Scaffold(
      appBar: BrandAppBar(
        titleSpacing: isDesktop ? 20 : 16,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: isDesktop
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: SearchBarWidget(
                      controller: _controller,
                      readOnly: false,
                      autoFocus: widget.initialKeyword == null,
                      onTap: () {},
                      onChanged: _onQueryChanged,
                      onSubmitted: _performSearch,
                    ),
                  ),
                )
              : SearchBarWidget(
                  controller: _controller,
                  readOnly: false,
                  autoFocus: widget.initialKeyword == null,
                  onTap: () {},
                  onChanged: _onQueryChanged,
                  onSubmitted: _performSearch,
                ),
        ),
      ),
      body: isDesktop
          ? Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: body,
              ),
            )
          : body,
    );
  }

  Widget _buildSearchResults(bool isDark) {
    if (_searchResults.isEmpty) {
      return BrandEmpty(
        title: '还没有找到这个故事',
        subtitle: '试试更短的名字，或者换一个关键词。',
        action: BrandButton(
          label: '重新寻找',
          icon: Icons.search_rounded,
          onPressed: () {
            _searchRequestId++;
            setState(() {
              _isSearching = false;
              _isLoadingMore = false;
              _hasSearched = false;
              _hasMore = false;
              _controller.clear();
              _searchResults.clear();
            });
            _loadSuggestions('');
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '搜索结果 ${_searchResults.length} / $_total 部',
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
            controller: _resultsScrollController,
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
            itemCount: _searchResults.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _searchResults.length) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
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
              const BrandPageBanner(
                title: '寻找心动的故事',
                subtitle: '记得一个名字，就能再次相遇。',
                eyebrow: 'FIND YOUR NEXT STORY',
              ),
              if (_suggestions.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      _suggestionsAreHot ? '大家在搜' : '搜索建议',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    if (_isLoadingSuggestions) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestions.map((item) {
                    return BrandPill(
                      label: Text(item),
                      onPressed: () {
                        _controller.text = item;
                        _performSearch(item);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],
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
                    return BrandPill(
                      label: Text(item),
                      onPressed: () {
                        _controller.text = item;
                        _performSearch(item);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        );
      },
    );
  }
}
