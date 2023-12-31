import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../widgets/brand_controls.dart';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/anime_poster_card.dart';
import 'anime_detail_screen.dart';
import 'settings_screen.dart';
import 'account_screen.dart';
import 'growth_screen.dart';
import '../widgets/member_avatar.dart';
import 'player_screen.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Future<void> _resumeHistory(PlayHistoryItem item) async {
    final result = await ApiService().getVideoDetail(item.videoId);
    if (!mounted) return;
    final video = result['video'] as VideoRecord?;
    if (video == null || video.playGroups.every((g) => g.episodes.isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂时无法播放，请稍后重试')));
      return;
    }
    var group = item.routeIndex.clamp(0, video.playGroups.length - 1);
    if (video.playGroups[group].episodes.isEmpty) {
      group = video.playGroups.indexWhere((g) => g.episodes.isNotEmpty);
    }
    final episodes = video.playGroups[group].episodes;
    final matched = episodes.indexWhere((e) => e.name == item.episodeName);
    final episode = matched >= 0
        ? matched
        : item.episodeIndex.clamp(0, episodes.length - 1);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          video: video,
          initialGroupIndex: group,
          initialEpisodeIndex: episode,
          initialPosition: matched >= 0
              ? Duration(seconds: item.currentTime)
              : Duration.zero,
        ),
      ),
    );
  }

  void _showDisclaimerDialog(SiteConfig config) {
    showDialog(
      context: context,
      builder: (ctx) => BrandDialog(
        title: const Text('免责与合规声明'),
        content: SingleChildScrollView(
          child: Text(
            config.siteDisclaimer,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我已知晓'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        final favorites = appState.favoriteVideos;
        final history = appState.playHistory;
        final config = appState.siteConfig;

        return Scaffold(
          appBar: BrandAppBar(
            title: const Text('我的'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '设置',
                onPressed: _openSettings,
              ),
            ],
          ),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                MemberAvatar(
                                  avatar:
                                      appState.user?['avatar']?.toString() ??
                                      '',
                                  frame:
                                      appState.user?['decorations']?['frame']
                                          ?.toString() ??
                                      '',
                                  size: 64,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        appState.user?['nickname']
                                                    ?.toString()
                                                    .isNotEmpty ==
                                                true
                                            ? appState.user!['nickname']
                                                  .toString()
                                            : appState.user?['username']
                                                      ?.toString() ??
                                                  '热爱故事的你',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: memberColor(
                                            appState
                                                .user?['decorations']?['nickname_color'],
                                          ),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (appState
                                              .user?['decorations']?['badge']
                                              ?.toString()
                                              .isNotEmpty ==
                                          true)
                                        Text(
                                          appState.user!['decorations']['badge']
                                              .toString(),
                                          style: const TextStyle(
                                            color: Colors.indigo,
                                            fontSize: 12,
                                          ),
                                        ),
                                      SizedBox(height: 5),
                                      Text(
                                        appState.isLoggedIn
                                            ? '收藏与播放记录已关联账号'
                                            : '登录以同步收藏与播放记录',
                                        style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1,
                                          color: AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                if (!appState.isLoggedIn)
                                  FilledButton(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const AccountScreen(),
                                      ),
                                    ),
                                    child: const Text('登录 / 注册'),
                                  )
                                else ...[
                                  FilledButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const GrowthScreen(),
                                      ),
                                    ),
                                    icon: const Icon(Icons.stars_rounded),
                                    label: const Text('同好成长站 / 消息'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: appState.syncing
                                        ? null
                                        : appState.syncAccount,
                                    icon: const Icon(Icons.sync_rounded),
                                    label: Text(
                                      appState.syncing ? '同步中…' : '同步账号数据',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: appState.logout,
                                    child: const Text('退出登录'),
                                  ),
                                ],
                              ],
                            ),
                            if (appState.accountError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  appState.accountError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            const Text(
                              '“ 喜欢动画，也喜欢生活。\n   在更多的故事里，遇见更好的自己。 ”',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.8,
                                color: AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: isDark
                                ? [AppColors.darkCard, const Color(0xFF39314F)]
                                : [
                                    const Color(0xFFFFEDF8),
                                    const Color(0xFFF0E9FF),
                                  ],
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.favorite_rounded,
                              color: AppColors.rose,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                '每一份热爱，都有迹可循',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _tabController.animateTo(0),
                              child: const Text(
                                '我的追番',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 数据概览小卡片 (追番数, 历史数, 接口状态)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkCard
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${favorites.length}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.rose,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    '我的追番',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkCard
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${history.length}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    '播放足迹',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: _openSettings,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkCard
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                  ),
                                ),
                                child: const Column(
                                  children: [
                                    Icon(
                                      Icons.dns_rounded,
                                      size: 20,
                                      color: AppColors.emerald,
                                    ),
                                    SizedBox(height: 2),
                                    Text('设置', style: TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 吸顶 Tab
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  BrandTabs(
                    controller: _tabController,
                    tabs: [
                      Tab(text: '我的追番 (${favorites.length})'),
                      Tab(text: '播放历史 (${history.length})'),
                    ],
                  ),
                  isDark ? AppColors.darkBg : AppColors.lightBg,
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                // 1. 追番列表
                favorites.isEmpty
                    ? const BrandEmpty(
                        title: '把喜欢的故事放在这里',
                        subtitle: '在详情页点一下爱心，就能加入追番。',
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              ((MediaQuery.sizeOf(context).width - 32) / 180)
                                  .floor()
                                  .clamp(3, 7),
                          childAspectRatio: 0.58,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: favorites.length,
                        itemBuilder: (context, index) {
                          final video = favorites[index];
                          return AnimePosterCard(
                            video: video,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AnimeDetailScreen(videoId: video.id),
                                ),
                              );
                            },
                          );
                        },
                      ),

                // 2. 播放历史
                history.isEmpty
                    ? const BrandEmpty(
                        title: '故事，从第一集开始',
                        subtitle: '看过的作品会留在这里，随时回来继续。',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: history.length + 1,
                        itemBuilder: (context, index) {
                          if (index == history.length) {
                            return Center(
                              child: TextButton.icon(
                                onPressed: () => appState.clearPlayHistory(),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                ),
                                label: const Text('清空历史记录'),
                              ),
                            );
                          }
                          final item = history[index];
                          final timeStr = DateFormat('MM-dd HH:mm').format(
                            DateTime.fromMillisecondsSinceEpoch(item.timestamp),
                          );

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 48,
                                    height: 64,
                                    child: CachedNetworkImage(
                                      imageUrl: item.videoPicture,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) =>
                                          const Icon(Icons.movie_outlined),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.videoName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '上次观看到：${item.episodeName}',
                                        style: const TextStyle(
                                          color: AppColors.primary500,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: AppColors.primary500,
                                    size: 28,
                                  ),
                                  onPressed: () => _resumeHistory(item),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
          bottomSheet: Container(
            color: isDark ? AppColors.darkBg : AppColors.lightBg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _showDisclaimerDialog(config),
                  child: const Text('免责声明', style: TextStyle(fontSize: 11)),
                ),
                const Text('·', style: TextStyle(color: Colors.grey)),
                TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => BrandDialog(
                        title: const Text('友情推荐'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (config.friendLinks.isEmpty)
                              const Text('新的相遇正在路上，稍后再来看看。'),
                            ...config.friendLinks.map(
                              (link) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _launchUrl(link.url);
                                  },
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(link.name),
                                            if (link.description.isNotEmpty)
                                              Text(
                                                link.description,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Icon(
                                        Icons.north_east_rounded,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('友情链接', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final BrandTabs tabBar;
  final Color backgroundColor;

  _SliverAppBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
