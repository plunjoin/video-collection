import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/analytics_tracker.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/anime_poster_card.dart';
import '../widgets/desktop_horizontal_scroll.dart';
import '../widgets/brand_intro.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/episode_selector.dart';
import '../widgets/video_comments.dart';
import 'player_screen.dart';

class AnimeDetailScreen extends StatefulWidget {
  final int videoId;
  const AnimeDetailScreen({super.key, required this.videoId});
  @override
  State<AnimeDetailScreen> createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends State<AnimeDetailScreen> {
  bool _loading = true;
  VideoRecord? _video;
  List<VideoRecord> _related = [];
  @override
  void initState() {
    super.initState();
    AnalyticsTracker().screen('anime', targetId: widget.videoId);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await ApiService().getVideoDetail(widget.videoId);
    if (!mounted) return;
    setState(() {
      _video = result['video'] as VideoRecord?;
      _related = result['related'] as List<VideoRecord>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? AppColors.darkBg : Colors.white,
      body: Column(
        children: [
          DesktopWindowTitleBar(isDark: dark),
          Expanded(
            child: _loading
                ? const Center(child: BrandIntro())
                : _video == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('未能加载番剧详情'),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _load,
                          child: const Text('重新加载'),
                        ),
                      ],
                    ),
                  )
                : AnimeDetailContent(
                    video: _video!,
                    related: _related,
                    onPlay: (group, episode) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(
                          video: _video!,
                          initialGroupIndex: group,
                          initialEpisodeIndex: episode,
                        ),
                      ),
                    ),
                    onRelated: (video) => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => AnimeDetailScreen(videoId: video.id),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Credit {
  final String name;
  final String role;
  const _Credit(this.name, this.role);
}

List<_Credit> _creditsOf(VideoRecord video) {
  final people = <_Credit>[];
  void addAll(String raw, String fallbackRole) {
    for (final part in raw.split(RegExp(r'[,，、/|｜;；]+'))) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final matched = RegExp(r'^(.+?)[(（](.+?)[)）]$').firstMatch(text);
      if (matched != null) {
        people.add(_Credit(matched.group(1)!.trim(), matched.group(2)!.trim()));
      } else {
        people.add(_Credit(text, fallbackRole));
      }
    }
  }

  addAll(video.actor, '主演');
  addAll(video.director, '导演');
  final seen = <String>{};
  return [
    for (final person in people)
      if (seen.add(person.name)) person,
  ];
}

/// Layout is driven by the actual available width, including resized windows.
class AnimeDetailContent extends StatefulWidget {
  final VideoRecord video;
  final List<VideoRecord> related;
  final void Function(int group, int episode) onPlay;
  final ValueChanged<VideoRecord> onRelated;
  const AnimeDetailContent({
    super.key,
    required this.video,
    required this.related,
    required this.onPlay,
    required this.onRelated,
  });
  @override
  State<AnimeDetailContent> createState() => _AnimeDetailContentState();
}

class _AnimeDetailContentState extends State<AnimeDetailContent> {
  bool _expanded = false;
  bool _savingFavorite = false;
  int _tab = 0;
  int _commentTotal = 0;

  int get _episodeCount {
    var count = 0;
    for (final group in widget.video.playGroups) {
      if (group.episodes.length > count) count = group.episodes.length;
    }
    return count;
  }

  Future<void> _toggleFavorite() async {
    if (_savingFavorite) return;
    final state = context.read<AppStateProvider>();
    setState(() => _savingFavorite = true);
    try {
      await state.toggleFavorite(widget.video);
      if (mounted && state.accountError != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(state.accountError!)));
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  Future<void> _share() async {
    final video = widget.video;
    await Clipboard.setData(ClipboardData(text: video.name));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制片名，可以分享给同好')));
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final favorite = context.watch<AppStateProvider>().isFavorite(video.id);
    final credits = _creditsOf(video);
    final firstPlayable = video.playGroups.indexWhere(
      (group) => group.episodes.isNotEmpty,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 840;
        return ColoredBox(
          color: dark ? AppColors.darkBg : Colors.white,
          child: SingleChildScrollView(
            child: Column(
              key: desktop ? const ValueKey('desktop-detail-columns') : null,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(dark, firstPlayable),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        desktop ? 28 : 16,
                        16,
                        desktop ? 28 : 16,
                        28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _heading(dark),
                          const SizedBox(height: 16),
                          _actions(dark, favorite, firstPlayable),
                          const SizedBox(height: 8),
                          _tabs(dark),
                          const SizedBox(height: 8),
                          if (_tab == 0) _about(dark, credits),
                          if (_tab == 1) _episodes(firstPlayable),
                          if (_tab == 2) _cast(dark, credits),
                          if (_tab == 3)
                            VideoCommentSection(
                              videoId: video.id,
                              onTotal: (total) {
                                if (_commentTotal == total) return;
                                setState(() => _commentTotal = total);
                              },
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
    );
  }

  Widget _hero(bool dark, int firstPlayable) {
    final video = widget.video;
    final quote = video.subName.trim();
    return SizedBox(
      height: 248,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _cover(video.picture),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x00000000),
                  Color(0x99000000),
                ],
                stops: [0, .45, 1],
              ),
            ),
          ),
          if (Navigator.of(context).canPop())
            Positioned(
              top: 8,
              left: 8,
              child: _roundIcon(
                Icons.chevron_left_rounded,
                () => Navigator.of(context).maybePop(),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: _roundIcon(Icons.ios_share_rounded, _share),
          ),
          Center(
            child: Material(
              color: Colors.white.withValues(alpha: .92),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: firstPlayable < 0
                    ? null
                    : () => widget.onPlay(firstPlayable, 0),
                child: const SizedBox(
                  width: 58,
                  height: 58,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Color(0xFFFF5C9A),
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 14,
            child: Text(
              'bllii 出品',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .86),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (quote.isNotEmpty)
            Positioned(
              right: 16,
              left: 120,
              bottom: 28,
              child: Text(
                quote,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heading(bool dark) {
    final video = widget.video;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final meta = [
      video.year,
      video.area,
      ...video.tags.take(3),
    ].where((item) => item.isNotEmpty).join(' · ');
    final update = [
      if (_episodeCount > 0) '全$_episodeCount话',
      video.remarks,
    ].where((item) => item.isNotEmpty).join(' · ');
    final chips = [
      if (video.remarks.isNotEmpty) video.remarks,
      if (video.area.isNotEmpty) video.area,
      if (video.language.isNotEmpty) video.language,
    ].take(3);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 92, height: 122, child: _cover(video.picture)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      video.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ),
                  if (video.hits > 0) ...[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatAudienceCount(video.hits),
                          style: const TextStyle(
                            color: Color(0xFFFF8A34),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        Text(
                          '次播放',
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final chip in chips)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.rose.withValues(alpha: .45),
                          ),
                        ),
                        child: Text(
                          chip,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.rose,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
              if (update.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(update, style: TextStyle(fontSize: 12, color: muted)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions(bool dark, bool favorite, int firstPlayable) {
    return Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: firstPlayable < 0
                  ? null
                  : const LinearGradient(
                      colors: [Color(0xFFFF8BC4), Color(0xFFFF5C9A)],
                    ),
              color: firstPlayable < 0 ? AppColors.lightBorder : null,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextButton.icon(
              onPressed: firstPlayable < 0
                  ? null
                  : () => widget.onPlay(firstPlayable, 0),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(firstPlayable < 0 ? '暂无片源' : '立即观看'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _savingFavorite ? null : _toggleFavorite,
          icon: Icon(
            favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 18,
          ),
          label: Text(favorite ? '已追番' : '追番'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF8B6CFF),
            backgroundColor: dark
                ? const Color(0xFF2A2440)
                : const Color(0xFFF3EEFF),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: const StadiumBorder(),
          ),
        ),
        const SizedBox(width: 8),
        _roundIcon(Icons.ios_share_rounded, _share, filled: true),
      ],
    );
  }

  Widget _tabs(bool dark) {
    const labels = ['详情', '剧集', '角色', '讨论'];
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _tab = index),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Text(
                      index == 3 && _commentTotal > 0
                          ? '讨论 ${_commentTotal > 9999 ? formatAudienceCount(_commentTotal) : _commentTotal}'
                          : labels[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _tab == index
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: _tab == index
                            ? (dark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary)
                            : muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 3,
                      width: 22,
                      decoration: BoxDecoration(
                        color: _tab == index
                            ? AppColors.rose
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _about(bool dark, List<_Credit> credits) {
    final video = widget.video;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          '简介',
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        const SizedBox(height: 8),
        Text(
          video.content.isEmpty ? '暂无简介' : video.content,
          maxLines: _expanded ? null : 4,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
            height: 1.7,
            fontSize: 14,
            color: dark ? AppColors.darkTextPrimary : const Color(0xFF3D4663),
          ),
        ),
        if (video.content.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? '收起' : '展开'),
          ),
        if (video.tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in video.tags.take(8))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: dark ? AppColors.darkCard : const Color(0xFFF4F6FB),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#$tag',
                    style: TextStyle(
                      fontSize: 12,
                      color: dark
                          ? AppColors.darkTextSecondary
                          : const Color(0xFF8B93A7),
                    ),
                  ),
                ),
            ],
          ),
        if (credits.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionTitle(
            '角色介绍',
            action: '更多',
            onTap: () => setState(() => _tab = 2),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 168,
            child: DesktopHorizontalScroll(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: credits.length.clamp(0, 8),
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _creditCard(credits[index], dark),
              ),
            ),
          ),
        ],
        if (widget.related.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionTitle('相关推荐'),
          const SizedBox(height: 12),
          SizedBox(
            height: 196,
            child: DesktopHorizontalScroll(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.related.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = widget.related[index];
                  return AudiencePosterTile(
                    video: item,
                    onTap: () => widget.onRelated(item),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _episodes(int firstPlayable) {
    final video = widget.video;
    if (video.playGroups.isEmpty) return const Text('暂无可播放片源');
    return EpisodeSelectorWidget(
      playGroups: video.playGroups,
      currentGroupIndex: firstPlayable < 0 ? 0 : firstPlayable,
      currentEpisodeIndex: 0,
      onSelected: widget.onPlay,
    );
  }

  Widget _cast(bool dark, List<_Credit> credits) {
    if (credits.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text('暂时没有角色和演职员信息'),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final credit in credits) _creditCard(credit, dark)],
    );
  }

  Widget _creditCard(_Credit credit, bool dark) {
    final colors = [
      const Color(0xFF8E7CFF),
      const Color(0xFF5B8DEF),
      const Color(0xFFFF7EB3),
      const Color(0xFF5CC8C2),
    ];
    final color = colors[credit.name.hashCode.abs() % colors.length];
    return SizedBox(
      width: 108,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 108,
            height: 112,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: .85),
                  color.withValues(alpha: .45),
                ],
              ),
            ),
            child: Text(
              credit.name.isEmpty
                  ? '?'
                  : String.fromCharCode(credit.name.runes.first),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            credit.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          Text(
            credit.role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: dark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {String? action, VoidCallback? onTap}) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          const Spacer(),
          if (action != null)
            Text(action, style: TextStyle(fontSize: 12, color: muted)),
          if (action != null)
            Icon(Icons.chevron_right_rounded, size: 16, color: muted),
        ],
      ),
    );
  }

  Widget _cover(String url) {
    const fallback = ColoredBox(
      color: Color(0xFF1C2438),
      child: Center(
        child: Icon(
          Icons.movie_filter_outlined,
          color: Colors.white54,
          size: 36,
        ),
      ),
    );
    if (url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }

  Widget _roundIcon(
    IconData icon,
    VoidCallback onPressed, {
    bool filled = false,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: filled
          ? (dark ? AppColors.darkCard : const Color(0xFFF4F6FB))
          : Colors.black.withValues(alpha: .28),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 18,
            color: filled && !dark ? AppColors.lightTextPrimary : Colors.white,
          ),
        ),
      ),
    );
  }
}
