
import '../ui/kit.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/analytics_tracker.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../theme/brand_icons.dart';
import '../widgets/brand_controls.dart';
import 'player_screen.dart';

/// 观看历史中心：顶部「继续观看」大卡片直达断点，下方按时间分组。
class HistoryCenterScreen extends StatefulWidget {
  const HistoryCenterScreen({super.key});

  @override
  State<HistoryCenterScreen> createState() => _HistoryCenterScreenState();
}

class _HistoryCenterScreenState extends State<HistoryCenterScreen> {
  final Map<int, VideoRecord> _videoCache = {};

  @override
  void initState() {
    super.initState();
    AnalyticsTracker().screen('history_center');
  }

  Future<void> _resume(PlayHistoryItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final video =
          _videoCache[item.videoId] ?? await _loadVideo(item.videoId);
      if (!mounted) return;
      if (video == null ||
          video.playGroups.every((g) => g.episodes.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂时无法播放，请稍后重试')),
        );
        return;
      }
      var group = item.routeIndex.clamp(0, video.playGroups.length - 1);
      if (video.playGroups[group].episodes.isEmpty) {
        group = video.playGroups.indexWhere((g) => g.episodes.isNotEmpty);
      }
      final episodes = video.playGroups[group].episodes;
      final matched = episodes.indexWhere((e) => e.name == item.episodeName);
      final episode =
          matched >= 0 ? matched : item.episodeIndex.clamp(0, episodes.length - 1);
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载失败，请检查网络后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _busy = false;

  Future<VideoRecord?> _loadVideo(int id) async {
    final result = await ApiService().getVideoDetail(id);
    final video = result['video'] as VideoRecord?;
    if (video != null) _videoCache[id] = video;
    return video;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? AppColors.darkBg : const Color(0xFFF7F8FD);
    final cardColor = isDark ? AppColors.darkCard : Colors.white;
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFE5E7EB);
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final app = context.watch<AppStateProvider>();
    final history = app.playHistory;
    final continueItems = history.where(_isResumable).take(4).toList();
    final groups = _groupByDay(history);

    return Scaffold(
      backgroundColor: pageColor,
      appBar: BrandAppBar(
        title: const Text('观看历史'),
        actions: [
          if (history.isNotEmpty)
            TextButton(
              onPressed: () async {
                final app = context.read<AppStateProvider>();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('清空观看历史'),
                    content: const Text('本机的播放记录将被删除，且无法恢复。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
                if (ok == true && mounted) {
                  await app.clearPlayHistory();
                }
              },
              child: Text(
                '清空',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),
        ],
      ),
      body: history.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandIcon(
                    BIcons.history,
                    size: 44,
                    color: muted.withValues(alpha: 0.5),
                    monochrome: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '还没有观看记录\n去首页挑一部番开始吧',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: muted, height: 1.7),
                  ),
                ],
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (continueItems.isNotEmpty) ...[
                      _sectionHeader('继续观看', ink),
                      const SizedBox(height: 12),
                      for (final item in continueItems)
                        _continueCard(item, cardColor, borderColor, ink, muted),
                      const SizedBox(height: 24),
                    ],
                    for (final entry in groups.entries) ...[
                      _sectionHeader(entry.key, ink),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          children: [
                            for (final item in entry.value) _listTile(item, ink, muted),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  bool _isResumable(PlayHistoryItem item) =>
      item.currentTime > 10 &&
      item.duration > 0 &&
      item.currentTime < item.duration * 0.98;

  Map<String, List<PlayHistoryItem>> _groupByDay(
      List<PlayHistoryItem> history) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final map = <String, List<PlayHistoryItem>>{};
    for (final item in history) {
      final time = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
      final day = DateTime(time.year, time.month, time.day);
      final diff = today.difference(day).inDays;
      final label = diff <= 0
          ? '今天'
          : diff == 1
              ? '昨天'
              : diff <= 7
                  ? '本周早些时候'
                  : '更早';
      map.putIfAbsent(label, () => []).add(item);
    }
    return map;
  }

  Widget _sectionHeader(String text, Color ink) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF89C7), Color(0xFF80B6FF)],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink),
        ),
      ],
    );
  }

  Widget _continueCard(
      PlayHistoryItem item, Color cardColor, Color borderColor, Color ink,
      Color muted) {
    final progress = item.duration > 0
        ? (item.currentTime / item.duration).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 96,
              height: 62,
              color: _posterBg(),
              child: _poster(item.videoPicture),
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.episodeName} · 看到 ${_mmss(item.currentTime)} / ${_mmss(item.duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: muted.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.primary500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _busy ? null : () => _resume(item),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary600,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('续播', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Color _posterBg() =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F172A)
          : const Color(0xFFE2E8F0);

  Widget _poster(String url) {
    if (url.isEmpty) {
      return const Center(
        child: BrandIcon(BIcons.play, size: 20, color: Colors.white38),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Center(
        child: BrandIcon(BIcons.play, size: 20, color: Colors.white38),
      ),
    );
  }

  Widget _listTile(PlayHistoryItem item, Color ink, Color muted) {
    return ListTile(
      onTap: () => _resume(item),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 64,
          height: 42,
          child: _poster(item.videoPicture),
        ),
      ),
      title: Text(
        item.videoName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink),
      ),
      subtitle: Text(
        '${item.episodeName} · ${_timeLabel(item.timestamp)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: muted),
      ),
      trailing: BrandIcon(
        BIcons.chevronRight,
        size: 16,
        color: muted,
        monochrome: true,
      ),
    );
  }

  String _mmss(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _timeLabel(int ts) {
    final time = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${time.month}月${time.day}日';
  }
}
