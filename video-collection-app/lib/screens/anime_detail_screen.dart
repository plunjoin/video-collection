import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../widgets/brand_controls.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_widgets.dart';
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
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  VideoRecord? _video;
  List<VideoRecord> _relatedList = [];
  bool _isSynopsisExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
    });

    final res = await _apiService.getVideoDetail(widget.videoId);
    if (!mounted) return;
    setState(() {
      _video = res['video'] as VideoRecord?;
      _relatedList = (res['related'] as List<VideoRecord>?) ?? [];
      _isLoading = false;
    });
  }

  void _playEpisode(int groupIndex, int episodeIndex) {
    if (_video == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          video: _video!,
          initialGroupIndex: groupIndex,
          initialEpisodeIndex: episodeIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Scaffold(body: Center(child: BrandLoading()));
    }

    if (_video == null) {
      return Scaffold(
        appBar: BrandAppBar(title: const Text('详情')),
        body: const Center(child: Text('未能加载番剧详情')),
      );
    }

    final video = _video!;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 235,
            pinned: true,
            backgroundColor: isDark ? AppColors.darkCard : Colors.white,
            title: const BrandLogo(width: 100),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: video.picture,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.45),
                    placeholder: (_, url) =>
                        const Center(child: BrandLoading()),
                    errorWidget: (_, url, error) => const Center(
                      child: BrandLogo(width: 100, symbolOnly: true),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x886677A0),
                          Color(0x006677A0),
                          Color(0x336677A0),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: IconButton.filledTonal(
                      tooltip: '立即播放',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.35),
                      ),
                      onPressed:
                          video.playGroups.isNotEmpty &&
                              video.playGroups.first.episodes.isNotEmpty
                          ? () => _playEpisode(0, 0)
                          : null,
                      icon: const Icon(
                        Icons.play_arrow_rounded,
                        size: 38,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: CachedNetworkImage(
                      imageUrl: video.picture,
                      width: 100,
                      height: 138,
                      fit: BoxFit.cover,
                      placeholder: (_, url) => const SizedBox(
                        width: 100,
                        height: 138,
                        child: Center(child: BrandLoading()),
                      ),
                      errorWidget: (_, url, error) => const SizedBox(
                        width: 100,
                        height: 138,
                        child: Center(
                          child: BrandLogo(width: 70, symbolOnly: true),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          [video.year, video.area, video.typeName].where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          video.remarks,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 主体内容
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 立即播放与追番按钮行
                  Row(
                    children: [
                      Expanded(
                        child: BrandButton(
                          onPressed:
                              video.playGroups.isNotEmpty &&
                                  video.playGroups.first.episodes.isNotEmpty
                              ? () => _playEpisode(0, 0)
                              : null,
                          label:
                              video.playGroups.isNotEmpty &&
                                  video.playGroups.first.episodes.isNotEmpty
                              ? '立即观看'
                              : '暂无片源',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Consumer<AppStateProvider>(
                        builder: (context, appState, child) {
                          final isFav = appState.isFavorite(video.id);
                          return OutlinedButton.icon(
                            onPressed: () => appState.toggleFavorite(video),
                            icon: Icon(
                              isFav
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 18,
                              color: isFav ? AppColors.rose : null,
                            ),
                            label: Text(isFav ? '已在追番' : '加入追番'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isFav
                                  ? AppColors.rose
                                  : (isDark
                                        ? AppColors.darkTextPrimary
                                        : AppColors.lightTextPrimary),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              side: BorderSide(
                                color: isFav
                                    ? AppColors.rose
                                    : (isDark
                                          ? AppColors.darkBorder
                                          : AppColors.lightBorder),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 2. 题材标签 Wrap
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: video.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkCard
                              : AppColors.primary50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.primary200,
                          ),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.primary700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  // 3. 选集面板 (EpisodeSelector)
                  Row(
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
                            '选集播放',
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
                      Text(
                        video.remarks,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  EpisodeSelectorWidget(
                    playGroups: video.playGroups,
                    currentGroupIndex: 0,
                    currentEpisodeIndex: 0,
                    onSelected: (groupIndex, epIndex) {
                      _playEpisode(groupIndex, epIndex);
                    },
                  ),

                  const SizedBox(height: 24),

                  // 4. 剧情简介 (Synopsis)
                  Row(
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
                        '剧情简介',
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

                  const SizedBox(height: 8),

                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isSynopsisExpanded = !_isSynopsisExpanded;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.content,
                            maxLines: _isSynopsisExpanded ? null : 4,
                            overflow: _isSynopsisExpanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                _isSynopsisExpanded ? '收起简介' : '展开全文',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary500,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Icon(
                                _isSynopsisExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: AppColors.primary500,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 5. 制作阵容与声优
                  if (video.actor.isNotEmpty || video.director.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (video.director.isNotEmpty) ...[
                            Text(
                              '导演 / 监制：${video.director}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (video.actor.isNotEmpty)
                            Text(
                              '主演 / 声优：${video.actor}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 6. 相关番剧推荐 (Related Anime)
                  if (_relatedList.isNotEmpty) ...[
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '同好推荐 · 看了又看',
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
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 125,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _relatedList.length,
                        itemBuilder: (context, index) {
                          final rel = _relatedList[index];
                          return Container(
                            width: 150,
                            margin: const EdgeInsets.only(right: 12),
                            child: AnimePosterCard(
                              video: rel,
                              onTap: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AnimeDetailScreen(videoId: rel.id),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
