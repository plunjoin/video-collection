import 'package:cached_network_image/cached_network_image.dart';
import '../../shared/ui/kit.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/video_model.dart';
import '../../shared/providers/app_state_provider.dart';
import '../../shared/services/api_service.dart';
import '../../shared/utils/responsive.dart';
import '../../shared/widgets/anime_poster_card.dart';
import '../../shared/widgets/desktop_horizontal_scroll.dart';
import '../../shared/widgets/brand_controls.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/member_avatar.dart';
import '../../shared/widgets/window_drag_area.dart';
import './account_desktop_page.dart';
import './anime_detail_desktop_page.dart';
import './content_hub_desktop_page.dart';
import './growth_desktop_page.dart';
import './player_desktop_page.dart';
import './profile_edit_desktop_page.dart';
import './profile_hub_desktop_page.dart';
import './settings_desktop_page.dart';
import './timeline_desktop_page.dart';
import './watch_lobby_desktop_page.dart';
import '../../shared/widgets/update_dialog.dart';
import '../../shared/theme/brand_icons.dart';

class ProfileDesktopPage extends StatefulWidget {
  const ProfileDesktopPage({super.key});

  @override
  State<ProfileDesktopPage> createState() => _ProfileDesktopPageState();
}

class _ProfileDesktopPageState extends State<ProfileDesktopPage> {
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
        .push(MaterialPageRoute(builder: (_) => const SettingsDesktopPage()));
  }

  void _openAccount() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountDesktopPage()))
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
        .push(MaterialPageRoute(builder: (_) => const ProfileEditDesktopPage()));
  }

  void _openGrowth([int tab = 0]) {
    final state = context.read<AppStateProvider>();
    if (!state.isLoggedIn) {
      _openAccount();
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GrowthDesktopPage(initialTab: tab)))
        .then((_) {
          if (mounted) setState(() => _loadedFor = '');
        });
  }

  void _openDetail(VideoRecord video) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailDesktopPage(videoId: video.id)),
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
        builder: (_) => PlayerDesktopPage(
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

  /// 退出登录会清掉本机登录态，先确认再执行。
  Future<void> _confirmLogout(AppStateProvider appState) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新登录才能同步收藏与观看记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) await appState.logout();
  }

  void _showDisclaimerDialog(SiteConfig config) {
    showBrandSheet(
      context,
      isScrollControlled: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '免责与合规声明',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                config.siteDisclaimer,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('我已知晓'),
            ),
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
                    // 桌面端顶部让位条：给右上角原生窗口按钮留出空间，同时兼作拖拽区
                    // （个人中心是自定义头部，不走 BrandAppBar，需要自行预留）
                    if (kBrandAppBarTopInset > 0) ...[
                      SizedBox(
                        height: kBrandAppBarTopInset,
                        child: WindowDragArea(
                          enabled: true,
                          child: ColoredBox(color: pageColor),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.line,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _Shortcut(
                                icon: BIcons.library,
                                color: AppColors.brandBlue,
                                label: '我的追番',
                                badge: favorites.isEmpty
                                    ? null
                                    : '${favorites.length}',
                                onTap: () => _openFavorites(favorites),
                              ),
                              _Shortcut(
                                icon: BIcons.history,
                                color: AppColors.brandBlue,
                                label: '观看历史',
                                onTap: () => _openHistory(history, appState),
                              ),
                              _Shortcut(
                                icon: BIcons.download,
                                color: AppColors.brandBlue,
                                label: '离线缓存',
                                onTap: () => _soon('离线缓存'),
                              ),
                              _Shortcut(
                                icon: BIcons.star,
                                color: AppColors.brandBlue,
                                label: '我的收藏',
                                onTap: () => _openFavorites(favorites),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              _Shortcut(
                                icon: BIcons.live,
                                color: AppColors.brandPink,
                                label: '一起看大厅',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const WatchLobbyDesktopPage(),
                                  ),
                                ),
                              ),
                              _Shortcut(
                                icon: BIcons.download,
                                color: AppColors.brandPurple,
                                label: '创作中心',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ContentHubDesktopPage(),
                                  ),
                                ),
                              ),
                              _Shortcut(
                                icon: BIcons.grid,
                                color: AppColors.brandBlue,
                                label: '功能中心',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ProfileHubDesktopPage(),
                                  ),
                                ),
                              ),
                              _Shortcut(
                                icon: BIcons.flag,
                                color: AppColors.brandPink,
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
                      _emptyCard('看过的故事会留在这里，随时回来继续。', cardColor, isDark)
                    else
                      _continueCard(latest, cardColor, muted, isDark),
                    const SizedBox(height: 22),
                    _sectionTitle(
                      '我的追番',
                      trailing: '更新提醒',
                      onTrailing: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TimelineDesktopPage(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (favorites.isEmpty)
                      _emptyCard('在详情页点一下爱心，就能加入追番。', cardColor, isDark)
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
                                        borderRadius: BorderRadius.circular(AppRadius.md),
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
                                          color: AppColors.brandSolid,
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
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => _showDisclaimerDialog(config),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            child: Text(
                              '免责声明',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.muted,
                              ),
                            ),
                          ),
                        ),
                        Text('·', style: TextStyle(color: muted, fontSize: 12)),
                        GestureDetector(
                          onTap: () => _showLinks(config),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            child: Text(
                              '友情链接',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.muted,
                              ),
                            ),
                          ),
                        ),
                        Text('·', style: TextStyle(color: muted, fontSize: 12)),
                        GestureDetector(
                          onTap: () => _checkUpdate(context),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            child: Text(
                              '检查更新',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.muted,
                              ),
                            ),
                          ),
                        ),
                        if (appState.isLoggedIn) ...[
                          Text('·', style: TextStyle(color: muted, fontSize: 12)),
                          GestureDetector(
                            onTap: appState.syncing ? null : appState.syncAccount,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Text(
                                appState.syncing ? '同步中…' : '同步',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.muted,
                                ),
                              ),
                            ),
                          ),
                          Text('·', style: TextStyle(color: muted, fontSize: 12)),
                          GestureDetector(
                            onTap: () => _confirmLogout(appState),
                            behavior: HitTestBehavior.opaque,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Text(
                                '退出登录',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFEF4444),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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
                            child: const BrandIcon(
                              BIcons.plus,
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
                                  const BrandIcon(
                                    BIcons.medal,
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
                  icon: const BrandIcon(BIcons.edit, size: 16),
                  label: const Text('编辑资料'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
                // 桌面端不再放铃铛/设置圆形按钮：右上角是原生窗口按钮的位置，
                // 设置已收敛到侧栏底部与功能中心，通知走成长中心。
              ] else ...[
                FilledButton.icon(
                  onPressed: _openAccount,
                  icon: const BrandIcon(BIcons.login, size: 18),
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
        // 顶部设置/铃铛圆钮仅移动端显示：
        // 桌面壳（含窄窗口回退到本头部时）右上角是原生窗口按钮的位置，
        // 设置走侧栏底部/功能中心，通知走成长中心
        if (!Responsive.isDesktop(context)) ...[
          Row(
            children: [
              _CircleIcon(
                icon: BIcons.settings,
                tooltip: '设置',
                onTap: _openSettings,
              ),
              const Spacer(),
              _CircleIcon(
                icon: BIcons.bell,
                badge: _unread > 0,
                onTap: () => _openGrowth(4),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
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
                        child: const BrandIcon(
                          BIcons.plus,
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
                                const BrandIcon(
                                  BIcons.medal,
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
    VoidCallback? onTapTitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onTapTitle ?? onTrailing,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 4),
              const BrandIcon(
                BIcons.chevronRight,
                size: 14,
                color: AppColors.muted,
                monochrome: true,
              ),
            ],
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onTrailing,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                trailing,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              const BrandIcon(
                BIcons.chevronRight,
                size: 13,
                color: AppColors.muted,
                monochrome: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyCard(String text, Color color, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.line,
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: isDark ? AppColors.darkTextSecondary : AppColors.muted,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _continueCard(PlayHistoryItem item, Color color, Color muted, bool isDark) {
    final progress = item.duration > 0
        ? (item.currentTime / item.duration).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.line,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: CachedNetworkImage(
              imageUrl: item.videoPicture,
              width: 96,
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.episodeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: progress == 0 ? null : progress,
                    minHeight: 4,
                    backgroundColor: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE8EEF8),
                    color: AppColors.brandSolid,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '已观看 ${_clock(item.currentTime)} / ${_clock(item.duration)}',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _resumeHistory(item),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brandGradient,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x336C5CE7),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: BrandIcon(
                  BIcons.play,
                  color: Colors.white,
                  size: 20,
                  monochrome: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLinks(SiteConfig config) {
    showBrandSheet(
      context,
      isScrollControlled: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '友情推荐',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
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
                      const BrandIcon(BIcons.arrowUpRight, size: 16),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final BrandIconData icon;
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
    final button = Container(
        decoration: BoxDecoration(color: dark ? AppColors.darkCard : Colors.white, borderRadius: BorderRadius.circular(16)),
        child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 36, height: 36, child: BrandIcon(icon, size: 18)),
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
    // 调用处已经包了 Expanded，这里不能再包一层，否则两层 FlexParentData 冲突
    return InkWell(
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
    );
  }
}

class _Shortcut extends StatelessWidget {
  final BrandIconData icon;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.18 : 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Center(
                    child: BrandIcon(
                      icon,
                      color: color,
                      size: 20,
                      monochrome: true,
                    ),
                  ),
                ),
                if (badge != null)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: isDark ? AppColors.darkCard : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
                color: isDark ? AppColors.darkTextPrimary : AppColors.ink,
              ),
            ),
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
                      icon: const BrandIcon(BIcons.trash, size: 16),
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
                        icon: const BrandIcon(
                          BIcons.playCircle,
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
