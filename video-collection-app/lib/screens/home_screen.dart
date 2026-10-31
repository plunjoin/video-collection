import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../widgets/brand_controls.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/anime_poster_card.dart';
import '../widgets/desktop_horizontal_scroll.dart';
import '../widgets/hero_banner.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/leaderboard_card.dart';
import '../widgets/quick_nav.dart';
import '../widgets/search_bar_widget.dart';
import 'anime_detail_screen.dart';
import 'content_detail_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';
import 'timeline_screen.dart';
import '../theme/brand_icons.dart';

class HomeScreen extends StatefulWidget {
  final Function(int tabIndex) onSwitchTab;

  const HomeScreen({super.key, required this.onSwitchTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<VideoRecord> _heroBanners = [];
  List<VideoRecord> _airingList = [];
  List<VideoRecord> _recommendList = [];
  List<VideoRecord> _rankings = [];
  List<Map<String, dynamic>> _latestNews = [];
  String _recommendGenre = '全部';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isLoggedIn = context.read<AppStateProvider>().isLoggedIn;
      final requests = <Future<dynamic>>[
        _apiService.getVideos(page: 1, pageSize: 18, typeId: 4),
        _apiService.getRankings(),
        _apiService.getVideos(page: 1, pageSize: 12, typeId: 4, sort: 'hits'),
        _apiService
            .getContentFeed(kind: 'news', page: 1, pageSize: 5)
            .catchError((_) => <String, dynamic>{
                  'list': <Map<String, dynamic>>[],
                }),
        if (isLoggedIn) _apiService.getPersonalizedRecommendations(),
      ];
      final results = await Future.wait(requests);

      final videoData = results[0] as Map<String, dynamic>;
      final rankData = results[1] as Map<String, List<VideoRecord>>;
      final popularData = results[2] as Map<String, dynamic>;
      final newsData = results[3] as Map<String, dynamic>;
      final list = (videoData['list'] as List<VideoRecord>?) ?? [];
      final popular = (popularData['list'] as List<VideoRecord>?) ?? [];
      final personal = isLoggedIn
          ? results[4] as Map<String, dynamic>
          : <String, dynamic>{};
      final personalList = (personal['list'] as List<VideoRecord>?) ?? [];
      final ranks = rankData['anime'] ?? rankData['top'] ?? [];

      if (!mounted) return;
      setState(() {
        if (list.isNotEmpty) {
          _heroBanners = list.take(5).toList();
          _airingList = list.take(4).toList();
        }
        _recommendList = personalList.isNotEmpty
            ? personalList.take(12).toList()
            : popular.take(12).toList();
        _rankings = ranks.take(5).toList();
        _latestNews =
            (newsData['list'] as List<Map<String, dynamic>>? ?? [])
                .take(5)
                .toList();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openDetail(VideoRecord video) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailScreen(videoId: video.id)),
    );
  }

  void _openPlayer(VideoRecord video) {
    if (video.playGroups.isNotEmpty &&
        video.playGroups.first.episodes.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            video: video,
            initialGroupIndex: 0,
            initialEpisodeIndex: 0,
          ),
        ),
      );
    } else {
      _openDetail(video);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = Responsive.isDesktop(context);
    final contentWidth = Responsive.contentWidth(context);
    final isWideDesktop = isDesktop && contentWidth >= 980;

    return Scaffold(
      appBar: isDesktop
          ? BrandAppBar(
              title: const Text(
                '发现 · 推荐',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              actions: [
                IconButton(
                  icon: const BrandIcon(BIcons.forum),
                  tooltip: '资讯与社区',
                  onPressed: () => widget.onSwitchTab(3),
                ),
                IconButton(
                  icon: const BrandIcon(BIcons.refresh),
                  tooltip: '刷新数据',
                  onPressed: _loadData,
                ),
                const SizedBox(width: 12),
              ],
            )
          : BrandAppBar(
              titleSpacing: 16,
              title: Row(
                children: [
                  const BrandLogo(width: 104),
                  const SizedBox(width: 12),
                  // 胶囊搜索框
                  Expanded(
                    child: SearchBarWidget(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SearchScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const BrandIcon(BIcons.forum),
                  tooltip: '资讯与社区',
                  onPressed: () => widget.onSwitchTab(3),
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: BrandLoading())
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppColors.primary500,
              child: isWideDesktop
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 宽屏桌面左侧：轮播 + 金刚区 + 热播海报网格 + 精选推荐
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeroBanner(),
                                _buildQuickNav(),
                                _buildLatestNewsSection(isDark),
                                _buildAiringSection(
                                  isDark,
                                  Responsive.gridColumns(
                                    context,
                                    width: contentWidth - 382,
                                    itemMinWidth: 180,
                                    min: 2,
                                    max: 4,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _buildRecommendSection(isDark),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          // 宽屏桌面右侧：常驻新番热度榜 + 经典台词
                          SizedBox(
                            width: 330,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLeaderboardSection(isDark),
                                const SizedBox(height: 16),
                                _buildQuoteSection(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeroBanner(),
                          _buildQuickNav(),
                          _buildLatestNewsSection(isDark),
                          _buildAiringSection(
                            isDark,
                            Responsive.gridColumns(
                              context,
                              width: contentWidth,
                              itemMinWidth: 160,
                              min: 2,
                              max: 4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildRecommendSection(isDark),
                          const SizedBox(height: 16),
                          _buildLeaderboardSection(isDark),
                          _buildQuoteSection(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
            ),
    );
  }

  Widget _buildHeroBanner() {
    return HeroBannerWidget(
      banners: _heroBanners,
      onPlayTap: _openPlayer,
      onDetailTap: _openDetail,
    );
  }

  Widget _buildQuickNav() {
    return QuickNavWidget(
      onNavTap: (tabIndex) => widget.onSwitchTab(tabIndex),
      onTimelineTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TimelineScreen()),
      ),
      onHistoryTap: () => widget.onSwitchTab(4),
    );
  }

  Widget _buildLatestNewsSection(bool isDark) {
    if (_latestNews.isEmpty) return const SizedBox.shrink();
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '最新资讯',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onSwitchTab(3),
                  child: const Text('更多 →'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 236,
            // 桌面端横向列表需要拖动 / 滚轮支持，否则鼠标滚不动
            child: DesktopHorizontalScroll(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _latestNews.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = _latestNews[index];
                  final cover = item['cover']?.toString() ?? '';
                  final date = (DateTime.tryParse(
                            item['published_at']?.toString() ?? '',
                          ) ??
                          DateTime.tryParse(item['created_at']?.toString() ?? ''))
                      ?.toLocal();
                  final title = item['title']?.toString() ?? '';
                  final placeholder = BrandPosterFallback(title: title);
                  return SizedBox(
                    width: 264,
                    child: Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      color: isDark ? AppColors.darkCard : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          final id =
                              int.tryParse(item['id']?.toString() ?? '') ?? 0;
                          if (id <= 0) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ContentDetailScreen(
                                kind: 'news',
                                contentId: id,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 没有封面的资讯直接铺满文字区，不再保留图片占位
                            if (cover.isNotEmpty)
                              SizedBox(
                                height: 92,
                                child: CachedNetworkImage(
                                  imageUrl: cover,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => placeholder,
                                  errorWidget: (_, _, _) => placeholder,
                                ),
                              ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['title']?.toString() ?? '未命名资讯',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item['summary']?.toString() ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      date == null
                                          ? ''
                                          : DateFormat(
                                              'yyyy/MM/dd',
                                            ).format(date),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiringSection(bool isDark, int crossAxisCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '正在热播',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.rose.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'HOT',
                      style: TextStyle(
                        color: AppColors.rose,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => widget.onSwitchTab(1),
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      BrandIcon(
                        BIcons.chevronRight,
                        size: 16,
                        color: AppColors.primary500,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 1.3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
            ),
            itemCount: _airingList.length,
            itemBuilder: (context, index) {
              final video = _airingList[index];
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

  Widget _buildRecommendSection(bool isDark) {
    final recommendations = _recommendGenre == '全部'
        ? _recommendList
        : _recommendList
              .where((video) => video.tags.contains(_recommendGenre))
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '为你推荐',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
            ],
          ),
        ),
        DesktopHorizontalScroll(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['全部', '治愈', '恋爱', '奇幻', '热血']
                  .map(
                    (genre) => Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 10),
                      child: BrandPill(
                        label: Text(genre),
                        selected: _recommendGenre == genre,
                        onSelected: (_) =>
                            setState(() => _recommendGenre = genre),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        if (recommendations.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '这个题材的故事还在路上，试试其他分类吧。',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
        SizedBox(
          height: recommendations.isEmpty ? 0 : 145,
          child: DesktopHorizontalScroll(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recommendations.length,
              itemBuilder: (context, index) {
                final video = recommendations[index];
                return Container(
                  width: 170,
                  margin: const EdgeInsets.only(right: 12),
                  child: AnimePosterCard(
                    video: video,
                    onTap: () => _openDetail(video),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '新番热度榜',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => widget.onSwitchTab(2),
                child: const Text(
                  '完整榜单 >',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: List.generate(
              _rankings.length,
              (index) => LeaderboardCard(
                rank: index + 1,
                video: _rankings[index],
                onTap: () => _openDetail(_rankings[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuoteSection() {
    return Column(
      children: [BrandStoryBanner(onTap: () => widget.onSwitchTab(4))],
    );
  }
}
