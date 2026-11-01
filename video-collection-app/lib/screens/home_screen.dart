import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import '../ui/kit.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../theme/brand_icons.dart';
import '../utils/responsive.dart';
import '../widgets/brand_controls.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/desktop_horizontal_scroll.dart';
import '../widgets/episode_selector.dart' show formatAudienceCount;
import '../widgets/search_bar_widget.dart';
import 'anime_detail_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';

/// 首页：筛选栏 + 视频墙；左侧个人资料与菜单由全局侧栏承担。
class HomeScreen extends StatefulWidget {
  final Function(int tabIndex) onSwitchTab;

  const HomeScreen({super.key, required this.onSwitchTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<VideoRecord> _videoList = [];
  String _recommendGenre = '全部';
  // 'time' 走接口默认排序（最新发布），'hits' 按播放量。
  String _sort = 'time';

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
      final wantPersonal = isLoggedIn && _sort == 'time';
      final requests = <Future<dynamic>>[
        _apiService.getVideos(
          page: 1,
          pageSize: 24,
          typeId: 4,
          sort: _sort == 'hits' ? 'hits' : null,
        ),
        // 登录后且按最新发布浏览时，优先展示个性化推荐结果
        if (wantPersonal) _apiService.getPersonalizedRecommendations(),
      ];
      final results = await Future.wait(requests);

      final videoData = results[0] as Map<String, dynamic>;
      final apiList = (videoData['list'] as List<VideoRecord>?) ?? [];
      List<VideoRecord> videos = apiList;
      if (wantPersonal && results.length > 1) {
        final personal = results[1] as Map<String, dynamic>;
        final personalList = (personal['list'] as List<VideoRecord>?) ?? [];
        if (personalList.isNotEmpty) {
          videos = personalList.take(24).toList();
        }
      }

      if (!mounted) return;
      setState(() {
        _videoList = videos;
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

  void _playRandom() {
    final list = _filteredVideos;
    if (list.isEmpty) return;
    _openPlayer(list[Random().nextInt(list.length)]);
  }

  List<VideoRecord> get _filteredVideos {
    if (_recommendGenre == '全部') return _videoList;
    return _videoList
        .where((video) => video.tags.contains(_recommendGenre))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = Responsive.isDesktop(context);
    final contentWidth = Responsive.contentWidth(context);

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
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilterBar(isDark, stacked: contentWidth < 760),
                    const SizedBox(height: 18),
                    _buildVideoGrid(isDark),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // 筛选栏：题材胶囊 + 排序下拉 + 主操作按钮
  // ---------------------------------------------------------------------------

  Widget _buildFilterBar(bool isDark, {required bool stacked}) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final card = isDark ? AppColors.darkCard : Colors.white;

    final pills = DesktopHorizontalScroll(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: ['全部', '治愈', '恋爱', '奇幻', '热血']
              .map(
                (genre) => Padding(
                  padding: const EdgeInsets.only(right: 8),
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
    );

    final sortMenu = PopupMenuButton<String>(
      tooltip: '切换排序方式',
      position: PopupMenuPosition.under,
      color: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
      onSelected: (value) {
        if (value == _sort) return;
        setState(() => _sort = value);
        _loadData();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'time',
          height: 40,
          child: Text('最新发布', style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          value: 'hits',
          height: 40,
          child: Text('最多播放', style: TextStyle(fontSize: 13)),
        ),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _sort == 'hits' ? '最多播放' : '最新发布',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 5),
            BrandIcon(BIcons.chevronDown, size: 14, color: muted),
          ],
        ),
      ),
    );

    final shuffleButton = _ShuffleButton(
      isDark: isDark,
      enabled: _filteredVideos.isNotEmpty,
      onTap: _playRandom,
    );

    if (!stacked) {
      return Row(
        children: [
          Expanded(child: pills),
          const SizedBox(width: 12),
          sortMenu,
          const SizedBox(width: 10),
          shuffleButton,
        ],
      );
    }
    return Column(
      children: [
        Align(alignment: Alignment.centerLeft, child: pills),
        const SizedBox(height: 8),
        Row(children: [sortMenu, const Spacer(), shuffleButton]),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 视频墙
  // ---------------------------------------------------------------------------

  Widget _buildVideoGrid(bool isDark) {
    final videos = _filteredVideos;
    if (videos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: BrandEmpty(
          title: '这里还没有片子',
          subtitle: '换个题材筛选，或稍后再来看看。',
        ),
      );
    }

    final isWide = Responsive.isDesktop(context);
    final contentWidth = Responsive.contentWidth(context);
    final gridWidth = contentWidth - 40;
    final crossAxisCount = Responsive.gridColumns(
      context,
      width: gridWidth,
      itemMinWidth: isWide ? 236 : 168,
      min: 2,
      max: isWide ? 4 : 3,
    );
    final itemWidth =
        (gridWidth - 14 * (crossAxisCount - 1)) / crossAxisCount;
    // 封面 16:9 + 一行标题 + 一行数据，按实际列宽精确算比例避免溢出
    final aspectRatio = itemWidth / (itemWidth * 9 / 16 + 48);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 14,
        mainAxisSpacing: 16,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return _HomeVideoCard(
          video: video,
          isDark: isDark,
          onTap: () => _openDetail(video),
          onPlayTap: () => _openPlayer(video),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 筛选栏按钮
// ---------------------------------------------------------------------------

/// 橙色主操作按钮：随机开一部当前筛选里的片子。
class _ShuffleButton extends StatelessWidget {
  final bool isDark;
  final bool enabled;
  final VoidCallback onTap;

  const _ShuffleButton({
    required this.isDark,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '随机看一部',
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
        decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(19)),
        child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(19),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFA24B), Color(0xFFFF7A45)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandIcon(
                    BIcons.shuffle,
                    size: 16,
                    color: Colors.white,
                    monochrome: true,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '随机看一部',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 视频卡片：封面 + 播放浮层 + 标题 + 数据行
// ---------------------------------------------------------------------------

class _HomeVideoCard extends StatefulWidget {
  final VideoRecord video;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onPlayTap;

  const _HomeVideoCard({
    required this.video,
    required this.isDark,
    required this.onTap,
    required this.onPlayTap,
  });

  @override
  State<_HomeVideoCard> createState() => _HomeVideoCardState();
}

class _HomeVideoCardState extends State<_HomeVideoCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final muted = widget.isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final ink = widget.isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final remarks = video.remarks.trim();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(
                      imageUrl: video.picture,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => BrandPosterFallback(
                        title: video.name,
                      ),
                      errorWidget: (_, _, _) =>
                          BrandPosterFallback(title: video.name),
                    ),
                  ),
                  // 悬停时轻微压暗封面，突出播放按钮
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: _hover ? 1 : 0,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.black.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                  Center(
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 160),
                      scale: _hover ? 1.12 : 1,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: GestureDetector(
                          onTap: widget.onPlayTap,
                          child: const BrandIcon(
                            BIcons.play,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (remarks.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          remarks,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              video.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                BrandIcon(
                  BIcons.play,
                  size: 13,
                  color: muted,
                  monochrome: true,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${formatAudienceCount(video.hits)} 播放',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    [
                      if (video.typeName.isNotEmpty) video.typeName,
                      if (video.year.isNotEmpty) video.year,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
