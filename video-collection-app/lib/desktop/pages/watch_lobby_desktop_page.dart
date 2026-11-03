import 'dart:convert';

import '../../shared/ui/kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/video_model.dart';
import '../../shared/providers/app_state_provider.dart';
import '../../shared/services/analytics_tracker.dart';
import '../../shared/services/api_service.dart';
import '../../shared/theme/brand_icons.dart';
import '../../shared/widgets/brand_controls.dart';
import './account_desktop_page.dart';
import './player_desktop_page.dart';

/// 一起看大厅：房间码加入 / 最近房间 / 使用说明。
/// 建房入口在播放页的一起看面板（房间与影片绑定）。
class WatchLobbyDesktopPage extends StatefulWidget {
  const WatchLobbyDesktopPage({super.key});

  @override
  State<WatchLobbyDesktopPage> createState() => _WatchLobbyDesktopPageState();
}

class _RecentRoom {
  final String code;
  final String title;
  final int videoId;
  final int joinedAt;

  _RecentRoom({
    required this.code,
    required this.title,
    required this.videoId,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'title': title,
        'videoId': videoId,
        'joinedAt': joinedAt,
      };

  static _RecentRoom fromJson(Map<String, dynamic> json) => _RecentRoom(
        code: json['code']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        videoId: (json['videoId'] as num?)?.toInt() ?? 0,
        joinedAt: (json['joinedAt'] as num?)?.toInt() ?? 0,
      );
}

class _WatchLobbyDesktopPageState extends State<WatchLobbyDesktopPage> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  bool _busy = false;
  String? _error;
  List<_RecentRoom> _recentRooms = [];

  static const _recentKey = 'watch_recent_rooms';

  @override
  void initState() {
    super.initState();
    AnalyticsTracker().screen('watch_lobby');
    _restoreRecent();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _restoreRecent() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final raw = prefs.getString(_recentKey);
    if (raw == null) return;
    try {
      final list = (json.decode(raw) as List)
          .map((e) => _RecentRoom.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() => _recentRooms = list);
    } catch (_) {}
  }

  Future<void> _rememberRoom(_RecentRoom room) async {
    final next = [
      room,
      ..._recentRooms.where((r) => r.code != room.code),
    ].take(8).toList();
    _recentRooms = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recentKey, json.encode([for (final r in next) r.toJson()]));
    if (mounted) setState(() {});
  }

  Future<void> _forgetRoom(String code) async {
    _recentRooms = _recentRooms.where((r) => r.code != code).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentKey,
      json.encode([for (final r in _recentRooms) r.toJson()]),
    );
    if (mounted) setState(() {});
  }

  /// 加入房间：探取房间信息 → 打开对应影片的播放页并自动入房。
  Future<void> _join(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位房间码');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await ApiService().joinWatchRoom(code);
      final videoId = (snapshot['video_id'] as num?)?.toInt() ?? 0;
      final groupIndex = (snapshot['group_index'] as num?)?.toInt() ?? 0;
      final episodeIndex = (snapshot['episode_index'] as num?)?.toInt() ?? 0;
      final title = snapshot['title']?.toString() ?? '';
      await _rememberRoom(_RecentRoom(
        code: code,
        title: title,
        videoId: videoId,
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      if (!mounted) return;

      final result = await ApiService().getVideoDetail(videoId);
      if (!mounted) return;
      final video = result['video'] as VideoRecord?;
      if (video == null || video.playGroups.every((g) => g.episodes.isEmpty)) {
        setState(() => _error = '房间影片暂时无法播放，请稍后重试');
        return;
      }
      var group = groupIndex.clamp(0, video.playGroups.length - 1);
      if (video.playGroups[group].episodes.isEmpty) {
        group = video.playGroups.indexWhere((g) => g.episodes.isNotEmpty);
      }
      final episodes = video.playGroups[group].episodes;
      final episode = episodeIndex.clamp(0, episodes.length - 1);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerDesktopPage(
            video: video,
            initialGroupIndex: group,
            initialEpisodeIndex: episode,
            watchRoomCode: code,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final loggedIn = context.watch<AppStateProvider>().isLoggedIn;

    return Scaffold(
      backgroundColor: pageColor,
      appBar: BrandAppBar(title: const Text('一起看大厅')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 品牌渐变横幅
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFE8F1FF),
                      Color(0xFFF1EBFF),
                      Color(0xFFFFEAF5),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const BrandIcon(
                        BIcons.live,
                        size: 28,
                        color: AppColors.rose,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '和朋友同步追同一部番',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '房主控制播放，所有人实时跟随；消息会以弹幕飘在画面上',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 房间码加入
              _sectionTitle('输入房间码加入', ink),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: loggedIn
                    ? Column(
                        children: [
                          TextField(
                            controller: _codeController,
                            focusNode: _codeFocus,
                            textCapitalization: TextCapitalization.characters,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 10,
                              color: ink,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: 'ABC123',
                              hintStyle: TextStyle(
                                color: muted.withValues(alpha: 0.5),
                                letterSpacing: 10,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.primary500,
                                  width: 1.6,
                                ),
                              ),
                            ),
                            onSubmitted: _join,
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : () => _join(_codeController.text),
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const BrandIcon(BIcons.play, size: 16,
                                      color: Colors.white, monochrome: true),
                              label: Text(_busy ? '正在进入房间…' : '进入房间'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary600,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.rose,
                              ),
                            ),
                          ],
                        ],
                      )
                    : Column(
                        children: [
                          Text(
                            '一起看需要登录账号',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '登录后即可用房间码加入朋友的房间',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const AccountDesktopPage()),
                            ),
                            child: const Text('去登录'),
                          ),
                        ],
                      ),
              ),

              // 最近房间
              if (_recentRooms.isNotEmpty) ...[
                const SizedBox(height: 22),
                _sectionTitle('最近加入', ink),
                const SizedBox(height: 10),
                ..._recentRooms.map((room) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Color(0xFFFF89C7),
                              Color(0xFFAE8CFF),
                              Color(0xFF80B6FF),
                            ]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            room.code,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        title: Text(
                          room.title.isEmpty ? '一起看房间' : room.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                        subtitle: Text(
                          _timeAgo(room.joinedAt),
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                        trailing: IconButton(
                          icon: BrandIcon(
                            BIcons.close,
                            size: 16,
                            color: muted,
                            monochrome: true,
                          ),
                          tooltip: '移除记录',
                          onPressed: () => _forgetRoom(room.code),
                        ),
                        onTap: () => _join(room.code),
                      ),
                    )),
              ],

              const SizedBox(height: 22),

              // 使用说明
              _sectionTitle('怎么一起看？', ink),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    _stepRow(
                      '1',
                      '任意影片进入播放页，在「一起看」选项卡里为当前影片创建房间',
                      ink,
                      muted,
                    ),
                    const SizedBox(height: 12),
                    _stepRow(
                      '2',
                      '把渐变房间码发给朋友，朋友在这里输入即可秒进房间',
                      ink,
                      muted,
                    ),
                    const SizedBox(height: 12),
                    _stepRow(
                      '3',
                      '房主的播放/暂停/进度/倍速/切集，全员实时同步',
                      ink,
                      muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, Color ink) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: ink,
      ),
    );
  }

  Widget _stepRow(String no, String text, Color ink, Color muted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.primary600,
            shape: BoxShape.circle,
          ),
          child: Text(
            no,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, height: 1.6, color: ink),
          ),
        ),
      ],
    );
  }

  String _timeAgo(int ms) {
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    if (diff < 60000) return '刚刚';
    if (diff < 3600000) return '${diff ~/ 60000} 分钟前';
    if (diff < 86400000) return '${diff ~/ 3600000} 小时前';
    return '${diff ~/ 86400000} 天前';
  }
}
