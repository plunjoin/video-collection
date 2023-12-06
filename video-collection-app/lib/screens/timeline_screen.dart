import 'package:flutter/material.dart';
import '../widgets/brand_controls.dart';

import '../models/video_model.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_widgets.dart';
import '../utils/responsive.dart';
import '../widgets/anime_poster_card.dart';
import 'anime_detail_screen.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  List<VideoRecord> _today = [];
  List<VideoRecord> _yesterday = [];
  List<VideoRecord> _earlier = [];

  @override
  void initState() {
    super.initState();
    _loadLatest();
  }

  Future<void> _loadLatest() async {
    setState(() {
      _isLoading = true;
    });

    final res = await _apiService.getLatest();
    if (!mounted) return;
    setState(() {
      _today = res['today'] ?? [];
      _yesterday = res['yesterday'] ?? [];
      _earlier = res['earlier'] ?? [];
      _isLoading = false;
    });
  }

  void _openDetail(VideoRecord video) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailScreen(videoId: video.id)),
    );
  }

  Widget _buildSection(String title, Color badgeColor, List<VideoRecord> list) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (list.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '共 ${list.length} 部番剧更新',
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
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: Responsive.gridColumns(
              context,
              itemMinWidth: 160,
              min: 2,
              max: 5,
            ),
            childAspectRatio: 1.25,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          ),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final video = list[index];
            return AnimePosterCard(
              video: video,
              onTap: () => _openDetail(video),
            );
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(title: const Text('新番更新')),
      body: _isLoading
          ? const Center(child: BrandLoading())
          : RefreshIndicator(
              onRefresh: _loadLatest,
              color: AppColors.primary500,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    const BrandPageBanner(title: '今天，也有新的期待', subtitle: '不错过喜欢的每一集。', eyebrow: 'A NEW DAY, A NEW EPISODE'),
                    if (_today.isEmpty && _yesterday.isEmpty && _earlier.isEmpty) const BrandEmpty(title: '给期待一点时间', subtitle: '暂无更新，下拉刷新试试。'),
                    _buildSection('今日新番更新', AppColors.rose, _today),
                    _buildSection('昨日连载放送', AppColors.gold, _yesterday),
                    _buildSection('更早精彩更新', AppColors.primary500, _earlier),
                  ],
                ),
              ),
            ),
    );
  }
}
