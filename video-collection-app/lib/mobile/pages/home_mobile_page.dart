import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';

import '../../shared/ui/kit.dart';

import 'package:provider/provider.dart';

import '../../shared/models/video_model.dart';
import '../../shared/providers/app_state_provider.dart';
import '../../shared/services/api_service.dart';
import '../../shared/theme/brand_icons.dart';
import '../../shared/utils/responsive.dart';
import '../../shared/widgets/brand_controls.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/desktop_horizontal_scroll.dart';
import '../../shared/widgets/episode_selector.dart' show formatAudienceCount;
import '../../shared/widgets/search_bar_widget.dart';
import './anime_detail_mobile_page.dart';
import './player_mobile_page.dart';
import './search_mobile_page.dart';

/// 首页：筛选栏 + 视频墙；左侧个人资料与菜单由全局侧栏承担。
class HomeMobilePage extends StatefulWidget {
  final Function(int tabIndex) onSwitchTab;

  const HomeMobilePage({super.key, required this.onSwitchTab});

  @override
  State<HomeMobilePage> createState() => _HomeMobilePageState();
}

class _HomeMobilePageState extends State<HomeMobilePage> {
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
      MaterialPageRoute(builder: (_) => AnimeDetailMobilePage(videoId: video.id)),
    );
  }

  void _openPlayer(VideoRecord video) {
    if (video.playGroups.isNotEmpty &&
        video.playGroups.first.episodes.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerMobilePage(
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
                  icon: const BrandIcon(BIcons.forum, monochrome: true),
                  tooltip: '资讯与社区',
                  onPressed: () => widget.onSwitchTab(3),
                ),
                IconButton(
                  icon: const BrandIcon(BIcons.refresh, monochrome: true),
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
                            builder: (_) => const SearchMobilePage(),
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
        : AppColors.muted;
    final border = isDark ? AppColors.darkBorder : AppColors.line;
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
                    onSelected: (_) => setState(() => _recommendGenre = genre),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );

    // PopupMenuButton 内部写死 InkWell 且不暴露 hover 颜色参数，
    // 这里用局部 Theme 关掉悬停高亮和水波，保持胶囊纯净。
    final sortMenu = Theme(
      data: Theme.of(context).copyWith(
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: PopupMenuButton<String>(
        tooltip: '切换排序方式',
        position: PopupMenuPosition.under,
        color: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: border),
        ),
        // 悬停高亮贴住胶囊本身(圆角一致、无额外内边距),
        // 不再出现比胶囊大一圈的浅色底块。
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(AppRadius.pill),
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
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _sort == 'hits' ? '最多播放' : '最新发布',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.ink,
                ),
              ),
              const SizedBox(width: 5),
              BrandIcon(
                BIcons.chevronDown,
                size: 14,
                color: muted,
                monochrome: true,
              ),
            ],
          ),
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
        child: BrandEmpty(title: '这里还没有片子', subtitle: '换个题材筛选，或稍后再来看看。'),
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
    final itemWidth = (gridWidth - 14 * (crossAxisCount - 1)) / crossAxisCount;
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              gradient: AppColors.brandGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandSolid.withValues(alpha: 0.22),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                BrandIcon(
                  BIcons.shuffle,
                  size: 14,
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
                    height: 1.2,
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

// ---------------------------------------------------------------------------
// 视频卡片：封面 + 播放浮层 + 标题 + 数据行
// ---------------------------------------------------------------------------

class _HomeVideoCard extends StatelessWidget {
  final VideoRecord video;
  final bool isDark;
  final VoidCallback onTap;

  const _HomeVideoCard({
    required this.video,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final video = this.video;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final remarks = video.remarks.trim();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: CachedNetworkImage(
                      imageUrl: video.picture,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          BrandPosterFallback(title: video.name),
                      errorWidget: (_, _, _) =>
                          BrandPosterFallback(title: video.name),
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
                          color: AppColors.ink.withValues(alpha: 0.54),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
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
