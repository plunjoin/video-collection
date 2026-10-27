import 'dart:ui' as ui;

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
import '../widgets/brand_widgets.dart';
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
                          const SizedBox(height: 18),
                          if (_tab == 0) _about(dark, credits),
                          if (_tab == 1) _episodes(firstPlayable),
                          if (_tab == 2) _cast(dark, credits),
                          if (_tab == 3)
                            VideoCommentSection(
                              targetId: video.id,
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
          // 虚化背景：整块封面做高斯模糊，让上层文字与按钮始终清晰可读
          ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Transform.scale(scale: 1.18, child: _cover(video.picture)),
            ),
          ),
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
      if (video.hits > 0) '${formatAudienceCount(video.hits)} 次播放',
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
          child: SizedBox(
            width: 92,
            height: 122,
            child: _cover(video.picture, title: video.name),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
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
    final playable = firstPlayable >= 0;
    final line = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    const violet = Color(0xFF8B6CFF);

    return Row(
      children: [
        // 主按钮按内容宽度收窄，右侧动作紧跟其后，不再拉满整行
        SizedBox(
          height: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: playable
                  ? const LinearGradient(
                      colors: [Color(0xFFFF8BC4), Color(0xFFFF5C9A)],
                    )
                  : null,
              color: playable ? null : line,
              borderRadius: BorderRadius.circular(20),
              boxShadow: playable
                  ? const [
                      BoxShadow(
                        color: Color(0x26FF5C9A),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: TextButton.icon(
              onPressed: playable
                  ? () => widget.onPlay(firstPlayable, 0)
                  : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(playable ? '立即观看' : '暂无片源'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: _savingFavorite ? null : _toggleFavorite,
            icon: Icon(
              favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 17,
              color: favorite ? violet : muted,
            ),
            label: Text(favorite ? '已追番' : '追番'),
            style: OutlinedButton.styleFrom(
              foregroundColor: favorite ? violet : null,
              backgroundColor: favorite
                  ? violet.withValues(alpha: dark ? .18 : .08)
                  : (dark ? Colors.transparent : Colors.white),
              side: BorderSide(
                color: favorite ? violet.withValues(alpha: .35) : line,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              shape: const StadiumBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 40,
          height: 40,
          child: OutlinedButton(
            onPressed: _share,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
              backgroundColor: dark ? Colors.transparent : Colors.white,
              side: BorderSide(color: line),
              shape: const CircleBorder(),
            ),
            child: Icon(Icons.ios_share_rounded, size: 17, color: muted),
          ),
        ),
      ],
    );
  }

  Widget _tabs(bool dark) {
    const labels = ['详情', '剧集', '角色', '讨论'];
    final line = dark ? AppColors.darkBorder : AppColors.lightBorder;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: line, width: .8)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            _DetailTab(
              label: labels[index],
              first: index == 0,
              selected: _tab == index,
              trailing: index == 3 && _commentTotal > 0
                  ? (_commentTotal > 9999
                        ? formatAudienceCount(_commentTotal)
                        : '$_commentTotal')
                  : null,
              onTap: () => setState(() => _tab = index),
            ),
          const Spacer(),
        ],
      ),
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
    return SizedBox(
      width: 108,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 108,
              height: 112,
              child: BrandPosterFallback(
                title: credit.name,
                forceDark: dark,
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

  Widget _cover(String url, {String title = ''}) {
    final fallback = BrandPosterFallback(
      title: title,
      forceDark: true,
      showGlyph: title.isNotEmpty,
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

/// 详情页页签：左对齐文字 + 贴底粉色指示条，和分类页的 tab 语言一致。
class _DetailTab extends StatefulWidget {
  final String label;
  final bool selected;
  final bool first;
  final String? trailing;
  final VoidCallback onTap;

  const _DetailTab({
    required this.label,
    required this.selected,
    required this.first,
    required this.onTap,
    this.trailing,
  });

  @override
  State<_DetailTab> createState() => _DetailTabState();
}

class _DetailTabState extends State<_DetailTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: EdgeInsets.only(
              left: widget.first ? 0 : 26,
              right: 2,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.2,
                        fontWeight: widget.selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: widget.selected || _hovered ? ink : muted,
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: muted.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          widget.trailing!,
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.2,
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (widget.selected)
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 20,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: AppColors.rose,
                        borderRadius: BorderRadius.circular(2),
                      ),
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
