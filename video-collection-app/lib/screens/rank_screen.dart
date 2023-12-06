import 'package:flutter/material.dart';
import '../widgets/brand_controls.dart';

import '../models/video_model.dart';
import '../services/api_service.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/leaderboard_card.dart';
import 'anime_detail_screen.dart';

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
    final all = res['anime'] ?? res['top'] ?? [];

    if (!mounted) return;
    setState(() {
      _allRank = all;
      _cnAnimeRank = all
          .where((v) => v.typeId == 15 || v.area == '大陆')
          .toList();
      _jpAnimeRank = all
          .where((v) => v.typeId == 16 || v.area == '日本')
          .toList();
      if (_cnAnimeRank.isEmpty) _cnAnimeRank = all.take(3).toList();
      if (_jpAnimeRank.isEmpty) _jpAnimeRank = all.skip(1).toList();
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
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: list.length + 1,
      itemBuilder: (context, position) {
        if (position == 0) return const BrandPageBanner(title: '大家的热爱，都在这里', subtitle: '一起发现值得追的好故事。', eyebrow: 'STORIES WE ALL LOVE');
        final index = position - 1;
        return LeaderboardCard(
          rank: index + 1,
          video: list[index],
          onTap: () => _openDetail(list[index]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: BrandAppBar(
        title: const Text('人气排行榜'),
        bottom: BrandTabs(controller: _tabController,tabs: const [
            Tab(text: '总热度榜'),
            Tab(text: '日韩动漫'),
            Tab(text: '国产动漫'),
          ]),
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
