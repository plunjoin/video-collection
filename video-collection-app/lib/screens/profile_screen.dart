import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/anime_poster_card.dart';
import '../widgets/desktop_horizontal_scroll.dart';
import '../widgets/brand_controls.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/member_avatar.dart';
import 'account_screen.dart';
import 'anime_detail_screen.dart';
import 'content_hub_screen.dart';
import 'growth_screen.dart';
import 'player_screen.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';
import 'timeline_screen.dart';
import '../widgets/update_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _points = 0;
  int _level = 1;
  String _levelName = '';
  int _unread = 0;
  String _loadedFor = '';

  void _ensureExtras(AppStateProvider appState) {
    final key = appState.isLoggedIn ? '${appState.user?['id']}' : '';
    if (_loadedFor == key) return;
    _loadedFor = key;
    if (key.isEmpty) {
      _points = 0;
      _level = 1;
      _levelName = '';
      _unread = 0;
      return;
    }
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.userRequest('/api/user/points'),
        api.userRequest('/api/user/journey'),
        api.userRequest('/api/user/notifications?page=1&page_size=1'),
      ]);
      if (!mounted || _loadedFor.isEmpty) return;
      final wallet = results[0]['data'];
      final journey = results[1]['data'];
      final level = journey is Map ? journey['level'] : null;
      setState(() {
        _points = wallet is Map ? _asInt(wallet['balance']) : 0;
        _level = level is Map ? _asInt(level['level']).clamp(1, 99) : 1;
        _levelName = level is Map ? level['name']?.toString() ?? '' : '';
        _unread = _asInt(results[2]['unread_count']);
      });
    } catch (_) {}
  }

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  String _compact(int value) {
    if (value >= 10000) {
      final text = (value / 10000).toStringAsFixed(1);
      return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}万';
    }
    return '$value';
  }

  String _clock(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final minutes = safe ~/ 60;
    final remain = safe % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remain.toString().padLeft(2, '0')}';
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openAccount() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountScreen()))
        .then((_) {
          if (mounted) setState(() => _loadedFor = '');
        });
  }

  void _openProfileEdit() {
    final state = context.read<AppStateProvider>();
    if (!state.isLoggedIn) {
      _openAccount();
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ProfileEditScreen()));
  }

  void _openGrowth([int tab = 0]) {
    final state = context.read<AppStateProvider>();
    if (!state.isLoggedIn) {
      _openAccount();
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GrowthScreen(initialTab: tab)))
        .then((_) {
          if (mounted) setState(() => _loadedFor = '');
        });
  }

  void _openDetail(VideoRecord video) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailScreen(videoId: video.id)),
    );
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

  Future<void> _checkUpdate(BuildContext context) async {
    final state = context.read<AppStateProvider>();
    if (state.checkingUpdate) return;
    try {
      final info = await state.checkAppUpdate();
      if (!context.mounted) return;
      await showUpdateDialog(context, info);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败: $e')),
      );
    }
  }

  void _soon(String name) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$name 还在准备中')));
  }

  void _openFavorites(List<VideoRecord> videos) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VideoLibraryPage(
          title: '我的追番',
          videos: videos,
          onOpen: _openDetail,
        ),
      ),
    );
  }

  void _openHistory(List<PlayHistoryItem> history, AppStateProvider appState) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HistoryPage(
          history: history,
          onPlay: _resumeHistory,
          onClear: appState.clearPlayHistory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? AppColors.darkBg : const Color(0xFFF7F8FD);
    final cardColor = isDark ? AppColors.darkCard : Colors.white;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        _ensureExtras(appState);
        final favorites = appState.favoriteVideos;
        final history = appState.playHistory;
        final config = appState.siteConfig;
        final user = appState.user;
        final isLoggedIn = appState.isLoggedIn;
        final nickname = user?['nickname']?.toString().trim().isNotEmpty == true
            ? user!['nickname'].toString()
            : user?['username']?.toString() ?? '星空下的旅人';
        final bio = isLoggedIn
            ? (user?['bio']?.toString().trim().isNotEmpty == true
                ? user!['bio'].toString().trim()
                : '“ 喜欢动画，也喜欢生活。\n在更多的故事里，遇见更好的自己。 ”')
            : '登录后可同步多端追番、播放历史和积分特权';
        final badge = user?['decorations']?['badge']?.toString() ?? '';
        final latest = history.isEmpty ? null : history.first;
        final wideDesktop =
            Responsive.isDesktop(context) &&
            Responsive.contentWidth(context) >= 900;

        return Scaffold(
          backgroundColor: pageColor,
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wideDesktop ? 1120 : double.infinity,
                ),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    wideDesktop ? 28 : 16,
                    wideDesktop ? 20 : 8,
                    wideDesktop ? 28 : 16,
                    28,
                  ),
                  children: [
                    if (wideDesktop)
                      _buildDesktopHeader(
                        context,
                        appState,
                        user,
                        nickname,
                        bio,
                        badge,
                        isDark,
                        cardColor,
                        muted,
                        favorites,
                        history,
                      )
                    else
                      _buildMobileHeader(
                        context,
                        appState,
                        user,
                        nickname,
                        bio,
                        badge,
                        isDark,
                        cardColor,
                        muted,
                        favorites,
                        history,
                      ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _Shortcut(
                                icon: Icons.smart_display_rounded,
                                color: const Color(0xFF4DA3FF),
                                label: '我的追番',
                                badge: favorites.isEmpty
                                    ? null
                                    : '${favorites.length}',
                                onTap: () => _openFavorites(favorites),
                              ),
                              _Shortcut(
                                icon: Icons.history_rounded,
                                color: const Color(0xFF4DA3FF),
                                label: '观看历史',
                                onTap: () => _openHistory(history, appState),
                              ),
                              _Shortcut(
                                icon: Icons.download_rounded,
                                color: const Color(0xFF4DA3FF),
                                label: '离线缓存',
                                onTap: () => _soon('离线缓存'),
                              ),
                              _Shortcut(
                                icon: Icons.star_rounded,
                                color: const Color(0xFF4DA3FF),
                                label: '我的收藏',
                                onTap: () => _openFavorites(favorites),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _Shortcut(
                                icon: Icons.sports_esports_rounded,
                                color: const Color(0xFF4DA3FF),
                                label: '我的游戏',
                                onTap: () => _soon('我的游戏'),
                              ),
                              _Shortcut(
                                icon: Icons.file_download_outlined,
                                color: const Color(0xFFB07CFF),
                                label: '创作中心',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ContentHubScreen(),
                                  ),
                                ),
                              ),
                              _Shortcut(
                                icon: Icons.checkroom_rounded,
                                color: const Color(0xFFFF7EB6),
                                label: '主题换肤',
                                onTap: _openSettings,
                              ),
                              _Shortcut(
                                icon: Icons.flag_rounded,
                                color: const Color(0xFFFF7EB6),
                                label: '活动中心',
                                onTap: () => _openGrowth(3),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionTitle(
                      '继续观看',
                      trailing: '查看更多',
                      onTrailing: () => _openHistory(history, appState),
                    ),
                    const SizedBox(height: 10),
                    if (latest == null)
                      _emptyCard('看过的故事会留在这里，随时回来继续。', cardColor)
                    else
                      _continueCard(latest, cardColor, muted),
                    const SizedBox(height: 22),
                    _sectionTitle(
                      '我的追番',
                      trailing: '更新提醒',
                      onTrailing: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TimelineScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (favorites.isEmpty)
                      _emptyCard('在详情页点一下爱心，就能加入追番。', cardColor)
                    else
                      SizedBox(
                        height: 168,
                        child: DesktopHorizontalScroll(
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: favorites.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final video = favorites[index];
                              return GestureDetector(
                                onTap: () => _openDetail(video),
                                child: SizedBox(
                                  width: 108,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: CachedNetworkImage(
                                          imageUrl: video.picture,
                                          width: 108,
                                          height: 108,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, _, _) =>
                                              BrandPosterFallback(
                                                title: video.name,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        video.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        video.remarks.isEmpty
                                            ? '追番中'
                                            : video.remarks,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.primary500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => _showDisclaimerDialog(config),
                          child: const Text(
                            '免责声明',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        Text('·', style: TextStyle(color: muted)),
                        TextButton(
                          onPressed: () => _showLinks(config),
                          child: const Text(
                            '友情链接',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        Text('·', style: TextStyle(color: muted)),
                        TextButton(
                          onPressed: () => _checkUpdate(context),
                          child: const Text(
                            '检查更新',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        if (appState.isLoggedIn) ...[
                          Text('·', style: TextStyle(color: muted)),
                          TextButton(
                            onPressed: appState.syncing
                                ? null
                                : appState.syncAccount,
                            child: Text(
                              appState.syncing ? '同步中…' : '同步',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text('·', style: TextStyle(color: muted)),
                          TextButton(
                            onPressed: appState.logout,
                            child: const Text(
                              '退出',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopHeader(
    BuildContext context,
    AppStateProvider appState,
    Map<String, dynamic>? user,
    String nickname,
    String bio,
    String badge,
    bool isDark,
    Color cardColor,
    Color muted,
    List<VideoRecord> favorites,
    List<PlayHistoryItem> history,
  ) {
    final isLoggedIn = appState.isLoggedIn;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: isLoggedIn ? _openProfileEdit : _openAccount,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MemberAvatar(
                      avatar: user?['avatar']?.toString() ?? '',
                      frame: user?['decorations']?['frame']?.toString() ?? '',
                      size: 80,
                    ),
                    if (isLoggedIn)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: GestureDetector(
                          onTap: () => _openGrowth(1),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: AppColors.primary500,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: isLoggedIn ? _openProfileEdit : _openAccount,
                            child: Text(
                              nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: isLoggedIn
                                    ? memberColor(
                                        user?['decorations']?['nickname_color'],
                                      )
                                    : (isDark
                                        ? AppColors.darkTextPrimary
                                        : AppColors.lightTextPrimary),
                              ),
                            ),
                          ),
                        ),
                        if (isLoggedIn) ...[
                          const SizedBox(width: 8),
                          _LevelChip(level: _level),
                          if (badge.isNotEmpty || _levelName.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3D6),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.workspace_premium_rounded,
                                    size: 14,
                                    color: Color(0xFFE2A100),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    badge.isNotEmpty
                                        ? badge
                                        : (_levelName.isEmpty
                                            ? '初遇故事'
                                            : _levelName),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFC48400),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: isLoggedIn ? _openProfileEdit : _openAccount,
                      child: Text(
                        bio,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (isLoggedIn) ...[
                OutlinedButton.icon(
                  onPressed: _openProfileEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑资料'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _CircleIcon(
                  icon: Icons.notifications_none_rounded,
                  badge: _unread > 0,
                  onTap: () => _openGrowth(4),
                ),
                const SizedBox(width: 6),
                _CircleIcon(
                  icon: Icons.settings_outlined,
                  tooltip: '设置',
                  onTap: _openSettings,
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: _openAccount,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('立即登录'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: _compact(favorites.length),
                  label: '追番',
                  onTap: () => _openFavorites(favorites),
                ),
              ),
              _statDivider(isDark),
              Expanded(
                child: _Stat(
                  value: _compact(history.length),
                  label: '足迹',
                  onTap: () => _openHistory(history, appState),
                ),
              ),
              _statDivider(isDark),
              Expanded(
                child: _Stat(
                  value: _compact(_points),
                  label: '积分',
                  onTap: () => _openGrowth(0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeader(
    BuildContext context,
    AppStateProvider appState,
    Map<String, dynamic>? user,
    String nickname,
    String bio,
    String badge,
    bool isDark,
    Color cardColor,
    Color muted,
    List<VideoRecord> favorites,
    List<PlayHistoryItem> history,
  ) {
    final isLoggedIn = appState.isLoggedIn;
    return Column(
      children: [
        Row(
          children: [
            _CircleIcon(
              icon: Icons.settings_outlined,
              tooltip: '设置',
              onTap: _openSettings,
            ),
            const Spacer(),
            _CircleIcon(
              icon: Icons.notifications_none_rounded,
              badge: _unread > 0,
              onTap: () => _openGrowth(4),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: isLoggedIn ? _openProfileEdit : _openAccount,
                  child: MemberAvatar(
                    avatar: user?['avatar']?.toString() ?? '',
                    frame: user?['decorations']?['frame']?.toString() ?? '',
                    size: 72,
                  ),
                ),
                if (isLoggedIn)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: GestureDetector(
                      onTap: () => _openGrowth(1),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: AppColors.primary500,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: isLoggedIn ? _openProfileEdit : _openAccount,
                          child: Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isLoggedIn
                                  ? memberColor(
                                      user?['decorations']?['nickname_color'],
                                    )
                                  : (isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.lightTextPrimary),
                            ),
                          ),
                        ),
                      ),
                      if (isLoggedIn) ...[
                        const SizedBox(width: 6),
                        _LevelChip(level: _level),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isLoggedIn)
                    Row(
                      children: [
                        if (badge.isNotEmpty || _levelName.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3D6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.workspace_premium_rounded,
                                  size: 14,
                                  color: Color(0xFFE2A100),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  badge.isNotEmpty
                                      ? badge
                                      : (_levelName.isEmpty
                                          ? '初遇故事'
                                          : _levelName),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFC48400),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        TextButton(
                          onPressed: _openProfileEdit,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('编辑资料'),
                        ),
                      ],
                    )
                  else
                    TextButton(
                      onPressed: _openAccount,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('登录 / 注册'),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: isLoggedIn ? _openProfileEdit : _openAccount,
          child: Text(
            bio,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.7,
              color: muted,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _Stat(
              value: _compact(favorites.length),
              label: '追番',
              onTap: () => _openFavorites(favorites),
            ),
            _statDivider(isDark),
            _Stat(
              value: _compact(history.length),
              label: '足迹',
              onTap: () => _openHistory(history, appState),
            ),
            _statDivider(isDark),
            _Stat(
              value: _compact(_points),
              label: '积分',
              onTap: () => _openGrowth(0),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statDivider(bool isDark) => Container(
    width: 1,
    height: 28,
    color: isDark ? AppColors.darkBorder : const Color(0xFFE6EAF5),
  );

  Widget _sectionTitle(
    String title, {
    required String trailing,
    required VoidCallback onTrailing,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
        const Spacer(),
        GestureDetector(
          onTap: onTrailing,
          child: Text(
            trailing,
            style: const TextStyle(
              color: AppColors.lightTextSecondary,
              fontSize: 13,
            ),
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppColors.lightTextSecondary,
        ),
      ],
    );
  }

  Widget _emptyCard(String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.lightTextSecondary),
      ),
    );
  }

  Widget _continueCard(PlayHistoryItem item, Color color, Color muted) {
    final progress = item.duration > 0
        ? (item.currentTime / item.duration).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: item.videoPicture,
              width: 92,
              height: 64,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) =>
                  BrandPosterFallback(title: item.videoName),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.videoName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  item.episodeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress == 0 ? null : progress,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFE8EEF8),
                    color: const Color(0xFFFF8BC4),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '已观看 ${_clock(item.currentTime)} / ${_clock(item.duration)}',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _resumeHistory(item),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brandGradient,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLinks(SiteConfig config) {
    showDialog(
      context: context,
      builder: (ctx) => BrandDialog(
        title: const Text('友情推荐'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (config.friendLinks.isEmpty) const Text('新的相遇正在路上，稍后再来看看。'),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(link.name),
                            if (link.description.isNotEmpty)
                              Text(
                                link.description,
                                style: const TextStyle(fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.north_east_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool badge;
  final String? tooltip;
  const _CircleIcon({
    required this.icon,
    required this.onTap,
    this.badge = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = Material(
      color: dark ? AppColors.darkCard : Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 18)),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (tooltip == null)
          button
        else
          Tooltip(message: tooltip, child: button),
        if (badge)
          const Positioned(
            right: 2,
            top: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFFF5A7A),
                shape: BoxShape.circle,
              ),
              child: SizedBox(width: 8, height: 8),
            ),
          ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  final int level;
  const _LevelChip({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F3FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'LV.$level',
        style: const TextStyle(
          color: AppColors.primary500,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback onTap;
  const _Stat({required this.value, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? badge;
  final VoidCallback onTap;
  const _Shortcut({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 28),
                if (badge != null)
                  Positioned(
                    right: -14,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5A7A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _VideoLibraryPage extends StatelessWidget {
  final String title;
  final List<VideoRecord> videos;
  final ValueChanged<VideoRecord> onOpen;
  const _VideoLibraryPage({
    required this.title,
    required this.videos,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(title: Text(title)),
      body: videos.isEmpty
          ? const BrandEmpty(title: '还没有追番', subtitle: '在详情页点一下爱心，就能加入这里。')
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: ((MediaQuery.sizeOf(context).width - 32) / 180)
                    .floor()
                    .clamp(2, 7),
                childAspectRatio: 0.58,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              itemCount: videos.length,
              itemBuilder: (context, index) => AnimePosterCard(
                video: videos[index],
                onTap: () => onOpen(videos[index]),
              ),
            ),
    );
  }
}

class _HistoryPage extends StatelessWidget {
  final List<PlayHistoryItem> history;
  final ValueChanged<PlayHistoryItem> onPlay;
  final VoidCallback onClear;
  const _HistoryPage({
    required this.history,
    required this.onPlay,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: const BrandAppBar(title: Text('观看历史')),
      body: history.isEmpty
          ? const BrandEmpty(title: '故事，从第一集开始', subtitle: '看过的作品会留在这里。')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length + 1,
              itemBuilder: (context, index) {
                if (index == history.length) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: () {
                        onClear();
                        Navigator.of(context).maybePop();
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('清空历史记录'),
                    ),
                  );
                }
                final item = history[index];
                final timeStr = DateFormat(
                  'MM-dd HH:mm',
                ).format(DateTime.fromMillisecondsSinceEpoch(item.timestamp));
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
                        child: CachedNetworkImage(
                          imageUrl: item.videoPicture,
                          width: 48,
                          height: 64,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => BrandPosterFallback(
                            title: item.videoName,
                            showGlyph: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.videoName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
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
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: AppColors.lightTextSecondary,
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
                        onPressed: () => onPlay(item),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
