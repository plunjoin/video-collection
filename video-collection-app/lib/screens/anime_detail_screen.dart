import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../widgets/brand_controls.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/brand_intro.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/anime_poster_card.dart';
import '../widgets/episode_selector.dart';
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
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        DesktopWindowTitleBar(
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
        Expanded(
          child: Scaffold(
            appBar: BrandAppBar(
              title: Text(
                _video?.name ?? '番剧详情',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            body: _loading
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
        ),
      ],
    ),
  );
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
  Widget _poster(double width) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: CachedNetworkImage(
      imageUrl: widget.video.picture,
      width: width,
      height: width * 1.4,
      fit: BoxFit.cover,
      placeholder: (_, url) => const Center(child: BrandLoading()),
      errorWidget: (_, url, error) => SizedBox(
        width: width,
        height: width * 1.4,
        child: const Center(child: BrandLogo(width: 72, symbolOnly: true)),
      ),
    ),
  );
  Widget _section(String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final state = context.watch<AppStateProvider>();
    final firstPlayable = video.playGroups.indexWhere(
      (group) => group.episodes.isNotEmpty,
    );
    final favorite = state.isFavorite(video.id);
    final synopsis = _section(
      '剧情简介',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            video.content.isEmpty ? '暂无简介' : video.content,
            maxLines: _expanded ? null : 6,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(height: 1.8),
          ),
          if (video.content.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起简介' : '展开全文'),
            ),
          if (video.director.isNotEmpty) Text('导演 / 监制：${video.director}'),
          if (video.actor.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('声优 / 主演：${video.actor}'),
            ),
        ],
      ),
    );
    final episodes = _section(
      '选集播放',
      video.playGroups.isEmpty
          ? const Text('暂无可播放片源')
          : EpisodeSelectorWidget(
              playGroups: video.playGroups,
              currentGroupIndex: firstPlayable < 0 ? 0 : firstPlayable,
              currentEpisodeIndex: 0,
              onSelected: widget.onPlay,
            ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 840;
        final padding = desktop ? 32.0 : 16.0;
        final contentWidth = (constraints.maxWidth - padding * 2).clamp(
          0.0,
          1200.0,
        );
        final metadata = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              video.name,
              style: TextStyle(
                fontSize: desktop ? 32 : 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              [
                video.year,
                video.area,
                video.typeName,
              ].where((v) => v.isNotEmpty).join(' · '),
            ),
            const SizedBox(height: 8),
            Text(video.remarks),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: video.tags
                  .map((tag) => Chip(label: Text(tag)))
                  .toList(),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            BrandButton(
              onPressed: firstPlayable < 0
                  ? null
                  : () => widget.onPlay(firstPlayable, 0),
              label: firstPlayable < 0 ? '暂无片源' : '立即观看',
            ),
            OutlinedButton.icon(
              onPressed: _savingFavorite
                  ? null
                  : () async {
                      setState(() => _savingFavorite = true);
                      try {
                        await state.toggleFavorite(video);
                        if (context.mounted && state.accountError != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(state.accountError!)),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _savingFavorite = false);
                      }
                    },
              icon: Icon(
                favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              label: Text(favorite ? '已在追番' : '加入追番'),
            ),
          ],
        );
        return SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: contentWidth,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(desktop ? 28 : 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary
                                .withValues(alpha: .12),
                            Theme.of(context).colorScheme.surface,
                          ],
                        ),
                      ),
                      child: desktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _poster(200),
                                const SizedBox(width: 32),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      metadata,
                                      const SizedBox(height: 24),
                                      actions,
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _poster(90),
                                    const SizedBox(width: 16),
                                    Expanded(child: metadata),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                actions,
                              ],
                            ),
                    ),
                    const SizedBox(height: 24),
                    if (desktop)
                      Row(
                        key: const ValueKey('desktop-detail-columns'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: episodes),
                          const SizedBox(width: 24),
                          Expanded(flex: 4, child: synopsis),
                        ],
                      )
                    else ...[
                      episodes,
                      const SizedBox(height: 16),
                      synopsis,
                    ],
                    if (widget.related.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      Text(
                        '同好推荐 · 看了又看',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: (contentWidth / 170).floor().clamp(
                            2,
                            6,
                          ),
                          childAspectRatio: .62,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 18,
                        ),
                        itemCount: widget.related.length,
                        itemBuilder: (context, index) => AnimePosterCard(
                          video: widget.related[index],
                          onTap: () => widget.onRelated(widget.related[index]),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
