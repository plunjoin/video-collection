import 'package:flutter/material.dart';

import '../widgets/brand_controls.dart';

import '../models/video_model.dart';
import '../services/api_service.dart';
import '../utils/responsive.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/leaderboard_card.dart';
import 'anime_detail_screen.dart';
import '../theme/brand_icons.dart';

class RankScreen extends StatefulWidget {
  const RankScreen({super.key});

  @override
  State<RankScreen> createState() => _RankScreenState();
}

class _RankScreenState extends State<RankScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  List<VideoRecord> _allRank = [];
  List<VideoRecord> _jpAnimeRank = [];
  List<VideoRecord> _cnAnimeRank = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRankings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRankings() async {
    setState(() {
      _isLoading = true;
    });

    final res = await _apiService.getRankings();
    final overall = res['top'] ?? [];
    final anime = res['anime'] ?? [];

    if (!mounted) return;
    setState(() {
      _allRank = overall;
      _cnAnimeRank = anime
          .where(
            (video) =>
                video.typeId == 15 ||
                video.area.contains('大陆') ||
                video.area.contains('中国'),
          )
          .toList();
      _jpAnimeRank = anime
          .where(
            (video) =>
                video.typeId == 16 ||
                video.area.contains('日本') ||
                video.area.contains('日韩'),
          )
          .toList();
      _isLoading = false;
    });
  }

  void _openDetail(VideoRecord video) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailScreen(videoId: video.id)),
    );
  }

  Widget _buildRankList(List<VideoRecord> list) {
    if (list.isEmpty) {
      return const BrandEmpty(title: '热爱正在汇集', subtitle: '这个榜单暂时没有作品，稍后再来看看。');
    }
    final listView = ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: list.length + 1,
      itemBuilder: (context, position) {
        if (position == 0) {
          return const BrandPageBanner(
            title: '大家的热爱，都在这里',
            subtitle: '一起发现值得追的好故事。',
            eyebrow: 'STORIES WE ALL LOVE',
          );
        }
        final index = position - 1;
        return LeaderboardCard(
          rank: index + 1,
          video: list[index],
          onTap: () => _openDetail(list[index]),
        );
      },
    );
    if (Responsive.contentWidth(context) < 980) return listView;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: listView,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(
        title: const Text('人气排行榜'),
        actions: [
          IconButton(
            tooltip: '刷新榜单',
            onPressed: _loadRankings,
            icon: const BrandIcon(BIcons.refresh),
          ),
        ],
        bottom: BrandTabs(
          controller: _tabController,
          tabs: const [
            Tab(text: '总热度榜'),
            Tab(text: '日韩动漫'),
            Tab(text: '国产动漫'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: BrandLoading())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRankList(_allRank),
                _buildRankList(_jpAnimeRank),
                _buildRankList(_cnAnimeRank),
              ],
            ),
    );
  }
}
