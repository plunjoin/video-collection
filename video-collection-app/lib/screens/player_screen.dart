import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../widgets/brand_controls.dart';
import '../widgets/brand_player_controls.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../services/analytics_tracker.dart';
import '../services/fullscreen_service.dart';
import '../services/api_service.dart';
import '../services/client_playlist_service.dart';
import '../services/watch_together_service.dart';
import '../widgets/anime_poster_card.dart';
import '../widgets/desktop_horizontal_scroll.dart';
import '../widgets/brand_intro.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../utils/native_window.dart';
import '../widgets/danmaku_overlay.dart';
import '../widgets/episode_selector.dart';
import '../models/wiki_model.dart';
import '../widgets/rag_ask_sheet.dart';
import '../widgets/video_comments.dart';
import '../widgets/watch_together_panel.dart';
import 'account_screen.dart';
import 'anime_detail_screen.dart';
import '../theme/brand_icons.dart';

enum AspectRatioMode {
  contain, // 居中自适应
  widescreen, // 16:9 宽屏
  classic, // 4:3 经典
  fill, // 画面铺满
}

class PlayerScreen extends StatefulWidget {
  final VideoRecord video;
  final int initialGroupIndex;
  final int initialEpisodeIndex;
  final Duration initialPosition;

  /// 从一起看大厅/分享进入时携带的房间码：进入即自动加入房间。
  final String? watchRoomCode;

  const PlayerScreen({
    super.key,
    required this.video,
    this.initialGroupIndex = 0,
    this.initialEpisodeIndex = 0,
    this.initialPosition = Duration.zero,
    this.watchRoomCode,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late int _currentGroupIndex;
  late int _currentEpisodeIndex;
  late final AppStateProvider _appState;
  Duration? _resumePosition;
  bool _resumeThenPause = false; // 远端切集后加载完成即暂停（房主处于暂停态）
  ClientPlaylistService? _pendingPlaylist;
  ClientPlaylistService? _activePlaylist;
  Future<void> _openQueue = Future.value();
  int _sourceGeneration = 0;

  // MediaKit 流媒体底层播放器
  late final Player _player;
  late final VideoController _videoController;

  // 播放器状态流监听
  final List<StreamSubscription> _subscriptions = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasError = false;
  String _errorMessage = '';

  // 交互控制
  bool _showControls = true;
  bool _controlsHovered = false; // 鼠标悬停在控制层上（顶栏/底栏），暂停自动隐藏
  Timer? _hideControlsTimer;
  bool _isFullscreen = false;
  bool _isLocked = false;
  bool _changingFullscreen = false;
  final _fullscreen = FullscreenService();
  Timer? _historyTimer;
  bool _isAutoPlayingNext = false;
  int _nextCountdownSeconds = 3;
  Timer? _nextCountdownTimer;
  // ===== 桌面新版页面（滚动信息流 + 悬浮小窗 + 右栏面板） =====
  final ScrollController _pageScroll = ScrollController();
  bool _miniFloat = false; // 状态B：播放器悬浮为右下角小窗
  bool _miniDismissed = false; // 用户关闭了悬浮小窗
  Offset _miniDrag = Offset.zero; // 距右下角的拖拽偏移
  int _sideTab = 0; // 右栏：0 选集 / 1 AI 助手 / 2 一起看
  final TextEditingController _episodeSearch = TextEditingController();
  bool _synopsisOpen = false;
  double _lastPlayerH = 480;
  WikiSubject? _wiki;
  bool _liked = false;

  // 极光画质增强 (Aurora Clarity Enhance)
  bool _isEnhanced = true;

  // 画面比例
  AspectRatioMode _aspectMode = AspectRatioMode.contain;

  // 倍速
  double _currentSpeed = 1.0;

  // 长按倍速加速
  bool _isLongPressSpeeding = false;
  double _preLongPressSpeed = 1.0;
  double _boostSpeed = 2.0;

  // 播放器内嵌倍速面板
  bool _showSpeedPanel = false;

  // 音量与亮度 HUD
  double _volume = 100.0; // 0.0 ~ 100.0
  double _brightness = 1.0; // 0.2 ~ 1.0 软调节滤镜
  String _hudText = '';
  BrandIconData? _hudIcon;
  bool _showHud = false;
  Timer? _hideHudTimer;

  // 双击快进快退反馈
  String _quickSeekTip = '';
  bool _showQuickSeekTip = false;
  Timer? _quickSeekTipTimer;

  // 手势拖拽进度计算
  bool _isDraggingProgress = false;
  double _dragTargetSeconds = 0.0;

  // 全屏内嵌选集抽屉
  bool _showFullscreenDrawer = false;
  int _drawerRange = 0;

  // 播放页下半屏：视频 / 弹幕 / 一起看 / 评论。选集只使用剧集卡片。
  int _sheetIndex = 0;
  List<DanmakuItem> _danmaku = [];
  int _danmakuGeneration = 0;
  bool _sendingDanmaku = false;
  bool _savingFavorite = false;
  bool _favorite = false;
  int _commentTotal = 0;
  List<VideoRecord> _related = [];

  // 一起看：房主控制播放，成员自动跟随。
  late final WatchTogether _watch;
  DateTime _remoteApplyGuardUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCorrectiveSeekAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _lastHostPlaying = false;
  Timer? _watchSeekDebounce;

  // 极光超清色彩卷积矩阵 (对比度+10%, 饱和度+15%, 色彩通透)
  static const List<double> _auroraMatrix = [
    1.12,
    -0.06,
    -0.06,
    0.0,
    4.0,
    -0.06,
    1.12,
    -0.06,
    0.0,
    4.0,
    -0.06,
    -0.06,
    1.16,
    0.0,
    4.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
  ];

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppStateProvider>();
    _currentSpeed = _appState.playbackSpeed;
    _resumePosition = widget.initialPosition;
    _currentGroupIndex = widget.initialGroupIndex;
    _currentEpisodeIndex = widget.initialEpisodeIndex;

    AnalyticsTracker().screen('play', targetId: widget.video.id);
    AnalyticsTracker().event(
      'play',
      page: 'app://play',
      targetId: widget.video.id,
    );

    // 实例化媒体播放引擎
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024, // 32MB 极速缓冲
      ),
    );
    _videoController = VideoController(_player);

    _favorite = _appState.isFavorite(widget.video.id);
    _historyTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isPlaying && !_hasError) _recordHistory(countHit: false);
    });
    _listenPlayerStreams();
    _pageScroll.addListener(_syncMiniState);
    unawaited(_loadWiki());
    _setupWatchTogether();
    _loadAndPlayCurrentEpisode();
    unawaited(_loadRelated());
    unawaited(_loadDanmaku());
  }

  /// 初始化一起看同步引擎：注入播放器读写挂钩。
  void _setupWatchTogether() {
    _watch = WatchTogether();
    _watch.myUserId = (_appState.user?['id'] as num?)?.toInt();
    _watch.getPositionMs = () => _position.inMilliseconds;
    _watch.isPlaying = () => _isPlaying;
    _watch.getGroupIndex = () => _currentGroupIndex;
    _watch.getEpisodeIndex = () => _currentEpisodeIndex;
    _watch.getRate = () => _currentSpeed;
    _watch.applyRemoteState = _applyWatchRemoteState;
    _watch.showNotice = (message) {
      if (mounted) _showHudMessage(message, BIcons.live);
    };
    _watch.onChatArrived = _injectChatDanmaku;
    // 从一起看大厅进入：带着房间码直接入房
    final roomCode = (widget.watchRoomCode ?? '').trim().toUpperCase();
    if (roomCode.isNotEmpty) {
      unawaited(_watch.join(roomCode).catchError((Object _) => null));
    }
  }

  /// 群聊消息以「昵称：内容」的形式送上弹幕（顶部品牌粉，与普通弹幕区分）。
  void _injectChatDanmaku(WatchMessageView msg) {
    if (!mounted || !_appState.danmakuEnabled) return;
    final nowMs = _position.inMilliseconds;
    setState(() {
      // 清理一分钟前注入的聊天弹幕（飞行最长 8 秒，此时早已离场）。
      _danmaku = _danmaku
          .where((d) => d.id >= 0 || d.playTimeMs > nowMs - 60000)
          .toList();
      _danmaku = [
        ..._danmaku,
        DanmakuItem(
          id: -msg.id, // 负数 id 与真实弹幕区分，避免去重冲突
          playTimeMs: nowMs,
          mode: 0,
          color: '#FF89C7',
          content: '${msg.authorName}：${msg.content}',
          userId: msg.userId,
          authorName: msg.authorName,
        ),
      ];
    });
  }

  /// 无控制权的成员：本地播放控制被锁定，只读提示。
  bool _watchGuestLocked() {
    if (_watch.active && !_watch.canControl) {
      _showHudMessage('房主控制中', BIcons.live);
      return true;
    }
    return false;
  }

  /// 应用远端播放状态：切集 / 播放暂停 / 拖进度 / 倍速，按最小动作执行。
  void _applyWatchRemoteState(WatchRoomSnapshot snap) {
    if (!mounted) return;
    final episodeChanged =
        snap.groupIndex != _currentGroupIndex ||
        snap.episodeIndex != _currentEpisodeIndex;
    final target = Duration(milliseconds: snap.targetPositionMs);

    // 倍速跟随（房主开 2x 时成员不必被反复拽进度）
    if (snap.rate > 0 && (snap.rate - _currentSpeed).abs() > 0.01) {
      _currentSpeed = snap.rate;
      _player.setRate(snap.rate);
      _appState.setPlaybackSpeed(snap.rate);
    }

    if (episodeChanged) {
      _lastHostPlaying = snap.playing;
      _remoteApplyGuardUntil = DateTime.now().add(
        const Duration(milliseconds: 2500),
      );
      _switchEpisode(snap.groupIndex, snap.episodeIndex, remote: true);
      // 注意顺序：_switchEpisode 会先清空 resume，这里在其后挂载目标进度，
      // 媒体加载完成（duration 事件）时再精确对齐。
      _resumePosition = target;
      _resumeThenPause = !snap.playing;
      return;
    }
    // 时间窗守卫：应用远端状态后的一小段时间内不回推本地变化（自愈，不会卡死）。
    _remoteApplyGuardUntil = DateTime.now().add(
      const Duration(milliseconds: 1500),
    );
    _lastHostPlaying = snap.playing;
    if (snap.playing != _isPlaying) {
      if (snap.playing) {
        _player.play();
      } else {
        _player.pause();
      }
    }
    if (_duration <= Duration.zero) {
      // 媒体尚未加载完成，seek 是空操作：挂到 resume 机制，加载完成后精确对齐，
      // 否则这次对齐会被“吃掉”且版本号已标记应用，成员会停在旧进度。
      _resumePosition = target;
      _resumeThenPause = !snap.playing;
      return;
    }
    final drift = target.inMilliseconds - _position.inMilliseconds;
    if (drift.abs() > 1500 &&
        DateTime.now().isAfter(
          _lastCorrectiveSeekAt.add(const Duration(seconds: 6)),
        )) {
      // 漂移纠偏至少间隔 6 秒：跟随房主真实位置（宁可有少许延迟），
      // 避免房主短暂缓冲时成员被来回拽。房主主动操作走版本变更，不受此限制。
      _lastCorrectiveSeekAt = DateTime.now();
      _player.seek(target);
    }
  }

  /// 远端应用的时间窗守卫：窗口期内本地播放事件不回推（避免同步回环）。
  bool _isRemoteApplyActive() =>
      DateTime.now().isBefore(_remoteApplyGuardUntil);

  /// 拖进度 / 倍速等连续操作的同步推送做 500ms 防抖。
  void _syncSeekToRoom() {
    if (!_watch.active || !_watch.canControl || _isRemoteApplyActive()) return;
    _watchSeekDebounce?.cancel();
    _watchSeekDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      unawaited(
        _watch.pushState(
          playing: _isPlaying,
          positionMs: _position.inMilliseconds,
          rate: _currentSpeed,
        ),
      );
    });
  }

  void _seekWithSync(Duration target) {
    _player.seek(target);
    _syncSeekToRoom();
  }

  Future<void> _loadRelated() async {
    final result = await ApiService().getVideoDetail(widget.video.id);
    if (!mounted) return;
    final related = result['related'];
    if (related is! List<VideoRecord>) return;
    setState(() {
      _related = related
          .where((item) => item.id != widget.video.id)
          .take(12)
          .toList();
    });
  }

  @override
  void dispose() {
    _pageScroll.removeListener(_syncMiniState);
    _pageScroll.dispose();
    _episodeSearch.dispose();
    ++_sourceGeneration;
    unawaited(_pendingPlaylist?.dispose());
    if (!_hasError && _duration > Duration.zero) {
      _recordHistory(countHit: false);
    }
    // 兜底：离开播放页时恢复右上角原生窗口按钮（防止全屏态泄漏导致按钮消失）
    NativeWindow.setControlsVisible(true);
    _historyTimer?.cancel();
    _hideControlsTimer?.cancel();
    _hideHudTimer?.cancel();
    _quickSeekTipTimer?.cancel();
    _nextCountdownTimer?.cancel();
    _watchSeekDebounce?.cancel();
    _watch.dispose();

    for (final s in _subscriptions) {
      s.cancel();
    }
    unawaited(
      _openQueue.whenComplete(() async {
        await _player.dispose();
        await _activePlaylist?.dispose();
      }),
    );

    unawaited(_fullscreen.setEnabled(false).catchError((Object _) {}));
    super.dispose();
  }

  void _listenPlayerStreams() {
    _subscriptions.addAll([
      _player.stream.position.listen((pos) {
        if (!mounted || _isDraggingProgress) return;
        setState(() {
          _position = pos;
        });
      }),
      _player.stream.duration.listen((dur) {
        if (!mounted) return;
        setState(() {
          _duration = dur;
        });
        if (_resumePosition != null && dur > Duration.zero) {
          final resume = _resumePosition!;
          _resumePosition = null;
          if (resume > Duration.zero && resume < dur) {
            _player.seek(resume);
            // 有控制权者的恢复播放进度也要同步给房间：此前这条 seek 绕过了推送，
            // 房间目标仍停在旧位置，成员会按理想时间线一路冲到房主前面。
            _syncSeekToRoom();
          }
          if (_resumeThenPause) {
            _resumeThenPause = false;
            _player.pause();
          }
        }
      }),
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        setState(() {
          _isPlaying = playing;
        });
        _onLocalPlayingChanged(playing);
      }),
      _player.stream.buffering.listen((buffering) {
        if (!mounted) return;
        setState(() {
          _isBuffering = buffering;
        });
      }),
      _player.stream.buffer.listen((buf) {
        if (!mounted) return;
        setState(() {
          _buffer = buf;
        });
      }),
      _player.stream.completed.listen((completed) {
        if (!mounted) return;
        if (completed && !_isAutoPlayingNext) {
          _triggerAutoPlayNext();
        }
      }),
      _player.stream.error.listen((error) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = '流媒体加载异常: $error';
        });
      }),
    ]);
  }

  /// 本地播放态变化时推送状态；无控制权的成员只跟随远端，不推送。
  void _onLocalPlayingChanged(bool playing) {
    if (!_watch.active || _isRemoteApplyActive()) return;
    if (!_watch.canControl) return;
    if (playing == _lastHostPlaying) return;
    _lastHostPlaying = playing;
    unawaited(
      _watch.pushState(
        playing: playing,
        positionMs: _position.inMilliseconds,
        rate: _currentSpeed,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Future<void> _loadAndPlayCurrentEpisode() async {
    final generation = ++_sourceGeneration;
    await _pendingPlaylist?.dispose();
    if (!mounted || generation != _sourceGeneration) return;
    _pendingPlaylist = null;
    _nextCountdownTimer?.cancel();
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _isAutoPlayingNext = false;
    });

    final currentGroup =
        widget.video.playGroups.isNotEmpty &&
            _currentGroupIndex < widget.video.playGroups.length
        ? widget.video.playGroups[_currentGroupIndex]
        : null;

    final currentEp =
        currentGroup != null &&
            _currentEpisodeIndex < currentGroup.episodes.length
        ? currentGroup.episodes[_currentEpisodeIndex]
        : null;

    if (currentEp == null || currentEp.url.trim().isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = '未获取到当前剧集的有效播放地址';
      });
      return;
    }

    ClientPlaylistService? resource;
    try {
      await _openQueue;
      if (!mounted || generation != _sourceGeneration) return;
      await _player.pause();
      if (!mounted || generation != _sourceGeneration) return;
      var playUrl = currentEp.url.trim();
      if (RegExp(r'\.m3u8(?:[?#]|$)', caseSensitive: false).hasMatch(playUrl) ||
          (!RegExp(
                r'\.(?:mp4|webm|mkv|mov|avi)(?:[?#]|$)',
                caseSensitive: false,
              ).hasMatch(playUrl) &&
              RegExp(
                r'hls|m3u8',
                caseSensitive: false,
              ).hasMatch(currentGroup!.playerCode))) {
        resource = ClientPlaylistService();
        _pendingPlaylist = resource;
        try {
          playUrl = await resource.prepare(playUrl);
        } catch (error) {
          await resource.dispose();
          resource = null;
          debugPrint('客户端 M3U8 过滤失败，使用原始播放地址: $error');
        }
      }
      if (!mounted || generation != _sourceGeneration) {
        await resource?.dispose();
        return;
      }
      _pendingPlaylist = null;
      final nextResource = resource;
      _openQueue = _openQueue
          .then((_) async {
            if (!mounted || generation != _sourceGeneration) {
              await nextResource?.dispose();
              return;
            }
            final oldResource = _activePlaylist;
            _activePlaylist = nextResource;
            try {
              await _player.open(Media(playUrl), play: true);
            } finally {
              await oldResource?.dispose();
            }
            if (!mounted || generation != _sourceGeneration) return;
            await _player.setRate(_currentSpeed);
            await _player.setVolume(_volume);
            _recordHistory();
            _resetHideControlsTimer();
          })
          .catchError((Object error) {
            if (!mounted || generation != _sourceGeneration) return;
            setState(() {
              _hasError = true;
              _errorMessage = '视频源解析失败: $error';
            });
          });
      await _openQueue;
    } catch (e) {
      await resource?.dispose();
      if (!mounted || generation != _sourceGeneration) return;
      setState(() {
        _hasError = true;
        _errorMessage = '视频源解析失败: $e';
      });
    }
  }

  void _recordHistory({bool countHit = true}) {
    if (widget.video.playGroups.isEmpty ||
        _currentGroupIndex >= widget.video.playGroups.length) {
      return;
    }
    final group = widget.video.playGroups[_currentGroupIndex];
    if (_currentEpisodeIndex >= group.episodes.length) return;
    final ep = group.episodes[_currentEpisodeIndex];

    final position = _resumePosition ?? _position;
    final duration = _duration;
    final routeIndex = _currentGroupIndex;
    final episodeIndex = _currentEpisodeIndex;
    Future.microtask(
      () => _appState.addPlayHistory(
        video: widget.video,
        episodeName: ep.name,
        playerCode: group.playerCode,
        playUrl: ep.url,
        routeIndex: routeIndex,
        episodeIndex: episodeIndex,
        currentTime: position.inSeconds,
        duration: duration.inSeconds,
        countHit: countHit,
      ),
    );
  }

  // 触发连播下一集
  void _triggerAutoPlayNext() {
    if (!_appState.autoPlayNext) return;
    // 一起看模式下切集由房主控制，成员不自动连播。
    if (_watch.active && !_watch.isHost) return;
    final group = widget.video.playGroups[_currentGroupIndex];
    if (_currentEpisodeIndex + 1 >= group.episodes.length) return;

    setState(() {
      _isAutoPlayingNext = true;
      _nextCountdownSeconds = 3;
    });

    _nextCountdownTimer?.cancel();
    _nextCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_nextCountdownSeconds > 1) {
        setState(() {
          _nextCountdownSeconds--;
        });
      } else {
        timer.cancel();
        _playNextEpisode();
      }
    });
  }

  void _cancelAutoPlayNext() {
    _nextCountdownTimer?.cancel();
    setState(() {
      _isAutoPlayingNext = false;
    });
  }

  void _resetHideControlsTimer() {
    // 鼠标悬停在控制层（顶栏/底栏）上时不自动隐藏，保证标题栏随时可抓取拖动
    if (_controlsHovered) return;
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && !_controlsHovered) {
          setState(() {
            _showControls = false;
            _showFullscreenDrawer = false;
          });
        }
      });
    }
  }

  /// 鼠标进入控制层：取消自动隐藏
  void _enterControlsHover() {
    _controlsHovered = true;
    _hideControlsTimer?.cancel();
    if (mounted && !_showControls) {
      setState(() => _showControls = true);
    }
  }

  /// 鼠标离开控制层：恢复自动隐藏倒计时
  void _exitControlsHover() {
    _controlsHovered = false;
    _resetHideControlsTimer();
  }

  void _showHudMessage(String text, BrandIconData icon) {
    _hideHudTimer?.cancel();
    setState(() {
      _hudText = text;
      _hudIcon = icon;
      _showHud = true;
    });
    _hideHudTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _showHud = false;
        });
      }
    });
  }

  void _showQuickSeekFeedback(String text) {
    _quickSeekTipTimer?.cancel();
    setState(() {
      _quickSeekTip = text;
      _showQuickSeekTip = true;
    });
    _quickSeekTipTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _showQuickSeekTip = false;
        });
      }
    });
  }

  void _togglePlayPause() {
    if (_watchGuestLocked()) return;
    if (_isPlaying) _recordHistory(countHit: false);
    _player.playOrPause();
    _resetHideControlsTimer();
  }

  void _seekBy(int seconds) {
    if (_watchGuestLocked()) return;
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    _seekWithSync(target);

    _showQuickSeekFeedback(seconds > 0 ? '+$seconds秒' : '$seconds秒');
    _resetHideControlsTimer();
  }

  void _playNextEpisode() {
    final group = widget.video.playGroups[_currentGroupIndex];
    if (_currentEpisodeIndex + 1 < group.episodes.length) {
      _switchEpisode(_currentGroupIndex, _currentEpisodeIndex + 1);
    }
  }

  void _playPrevEpisode() {
    if (_currentEpisodeIndex > 0) {
      _switchEpisode(_currentGroupIndex, _currentEpisodeIndex - 1);
    }
  }

  void _switchEpisode(int groupIndex, int episodeIndex, {bool remote = false}) {
    if (!remote && _watchGuestLocked()) return;
    if (!_hasError && _duration > Duration.zero) {
      _recordHistory(countHit: false);
    }
    _resumePosition = null;
    _resumeThenPause = false;
    setState(() {
      _position = Duration.zero;
      _duration = Duration.zero;
      _currentGroupIndex = groupIndex;
      _currentEpisodeIndex = episodeIndex;
      _showFullscreenDrawer = false;
      _showSpeedPanel = false;
    });
    _loadAndPlayCurrentEpisode();
    unawaited(_loadDanmaku());
    if (!remote && _watch.active && _watch.canControl) {
      unawaited(
        _watch.pushState(
          groupIndex: groupIndex,
          episodeIndex: episodeIndex,
          playing: true,
          positionMs: 0,
          rate: _currentSpeed,
        ),
      );
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_changingFullscreen) return;
    _changingFullscreen = true;
    final next = !_isFullscreen;
    try {
      await _fullscreen.setEnabled(next);
      if (!mounted) {
        await _fullscreen.setEnabled(false);
        return;
      }
      setState(() {
        _isFullscreen = next;
        _showFullscreenDrawer = false;
        _showSpeedPanel = false;
      });
      // 全屏时隐藏右上角原生窗口控制按钮，退出全屏时恢复
      NativeWindow.setControlsVisible(!next);
      _syncMiniState();
      _resetHideControlsTimer();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法切换全屏，请重试')));
      }
    } finally {
      _changingFullscreen = false;
    }
  }

  /// 桌面非全屏时，顶部控制栏为右上角原生窗口控制按钮预留的让位高度。
  double _nativeWindowControlsInset() {
    if (_isFullscreen || !kIsWindowsDesktop) return 0;
    return Responsive.isDesktop(context) ? 40 : 0;
  }

  void _setSpeed(double speed) {
    if (_watchGuestLocked()) return;
    setState(() {
      _currentSpeed = speed;
    });
    _player.setRate(speed);
    unawaited(_appState.setPlaybackSpeed(speed));
    if (_watch.active && _watch.canControl) {
      unawaited(
        _watch.pushState(
          rate: speed,
          playing: _isPlaying,
          positionMs: _position.inMilliseconds,
        ),
      );
    }
    final speedStr = speed == speed.roundToDouble()
        ? '${speed.toInt()}.0'
        : ((speed * 10) % 1 == 0
              ? speed.toStringAsFixed(1)
              : speed.toStringAsFixed(2));
    _showHudMessage('${speedStr}x 倍速', BIcons.speed);
  }

  void _startLongPressSpeedUp() {
    if (_isLocked || !_isPlaying || _hasError || _isDraggingProgress) return;
    if (_watchGuestLocked()) return;
    _preLongPressSpeed = _currentSpeed;
    _boostSpeed = _currentSpeed >= 2.0 ? 3.0 : 2.0;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _isLongPressSpeeding = true;
      _showSpeedPanel = false;
    });
    _player.setRate(_boostSpeed);
  }

  void _stopLongPressSpeedUp() {
    if (!_isLongPressSpeeding) return;
    setState(() {
      _isLongPressSpeeding = false;
    });
    _player.setRate(_preLongPressSpeed);
  }

  void _toggleAspectMode() {
    setState(() {
      switch (_aspectMode) {
        case AspectRatioMode.contain:
          _aspectMode = AspectRatioMode.widescreen;
          _showHudMessage('画面比例: 16:9 宽屏', BIcons.ratio);
          break;
        case AspectRatioMode.widescreen:
          _aspectMode = AspectRatioMode.classic;
          _showHudMessage('画面比例: 4:3 经典', BIcons.ratio);
          break;
        case AspectRatioMode.classic:
          _aspectMode = AspectRatioMode.fill;
          _showHudMessage('画面比例: 铺满全屏', BIcons.fullscreen);
          break;
        case AspectRatioMode.fill:
          _aspectMode = AspectRatioMode.contain;
          _showHudMessage('画面比例: 居中自适应', BIcons.fit);
          break;
      }
    });
  }

  void _toggleEnhance() {
    setState(() {
      _isEnhanced = !_isEnhanced;
    });
    _showHudMessage(
      _isEnhanced ? '极光超清画质增强: 已开启' : '极光画质增强: 已关闭',
      BIcons.sparkles,
    );
  }

  // 键盘快捷键监听
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape && _isFullscreen) {
        _toggleFullscreen();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        _togglePlayPause();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _seekBy(5);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _seekBy(-5);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        final newVol = (_volume + 10).clamp(0.0, 100.0);
        setState(() => _volume = newVol);
        _player.setVolume(newVol);
        _showHudMessage('音量: ${newVol.toInt()}%', BIcons.volume);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        final newVol = (_volume - 10).clamp(0.0, 100.0);
        setState(() => _volume = newVol);
        _player.setVolume(newVol);
        _showHudMessage(
          '音量: ${newVol.toInt()}%',
          newVol == 0 ? BIcons.muted : BIcons.volumeLow,
        );
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.bracketRight) {
        _playNextEpisode();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.bracketLeft) {
        _playPrevEpisode();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _toggleFullscreen();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
        _toggleDanmaku();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
        final newVol = _volume > 0 ? 0.0 : 100.0;
        setState(() => _volume = newVol);
        _player.setVolume(newVol);
        _showHudMessage(
          newVol == 0 ? '静音' : '音量: ${newVol.toInt()}%',
          newVol == 0 ? BIcons.muted : BIcons.volume,
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _toggleDanmaku() {
    final next = !_appState.danmakuEnabled;
    _appState.setDanmakuEnabled(next);
    _showHudMessage(
      next ? '弹幕: 已开启' : '弹幕: 已关闭',
      next ? BIcons.message : BIcons.message,
    );
    _resetHideControlsTimer();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groups = widget.video.playGroups;
    final currentGroup = groups.isNotEmpty && _currentGroupIndex < groups.length
        ? groups[_currentGroupIndex]
        : null;
    final currentEp =
        currentGroup != null &&
            _currentEpisodeIndex < currentGroup.episodes.length
        ? currentGroup.episodes[_currentEpisodeIndex]
        : null;

    final playerCore = Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth < 560 || constraints.maxHeight < 280;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_showSpeedPanel) {
                setState(() {
                  _showSpeedPanel = false;
                });
                _resetHideControlsTimer();
                return;
              }
              if (_isLocked) {
                setState(() {
                  _showControls = !_showControls;
                });
                _resetHideControlsTimer();
                return;
              }
              setState(() {
                _showControls = !_showControls;
                if (!_showControls) _showFullscreenDrawer = false;
              });
              _resetHideControlsTimer();
            },
            onDoubleTapDown: (details) {
              if (_isLocked || _isLongPressSpeeding) return;
              // 桌面端双击 = 播放/暂停；移动端保留左右半屏快退快进
              if (Responsive.isDesktop(context)) return;
              final width = MediaQuery.of(context).size.width;
              if (details.localPosition.dx < width / 2) {
                _seekBy(-5);
              } else {
                _seekBy(5);
              }
            },
            onDoubleTap: () {
              if (_isLocked || _isLongPressSpeeding) return;
              if (!Responsive.isDesktop(context)) return;
              _togglePlayPause();
              _resetHideControlsTimer();
            },
            onLongPressStart: (details) => _startLongPressSpeedUp(),
            onLongPressEnd: (details) => _stopLongPressSpeedUp(),
            onLongPressCancel: () => _stopLongPressSpeedUp(),
            onVerticalDragUpdate: (details) {
              if (_isLocked || _isLongPressSpeeding) return;
              final width = MediaQuery.of(context).size.width;
              final delta = -details.primaryDelta! / 2.0;
              if (details.localPosition.dx > width / 2) {
                // 右半屏调音量
                final newVol = (_volume + delta).clamp(0.0, 100.0);
                setState(() => _volume = newVol);
                _player.setVolume(newVol);
                _showHudMessage(
                  '音量: ${newVol.toInt()}%',
                  newVol == 0 ? BIcons.muted : BIcons.volume,
                );
              } else {
                // 左半屏调亮度
                final newBri = (_brightness + delta / 100.0).clamp(0.2, 1.0);
                setState(() => _brightness = newBri);
                _showHudMessage('亮度: ${(newBri * 100).toInt()}%', BIcons.sun);
              }
            },
            onHorizontalDragStart: (details) {
              if (_isLocked || _isLongPressSpeeding) return;
              if (_watchGuestLocked()) return;
              _isDraggingProgress = true;
              _dragTargetSeconds = _position.inSeconds.toDouble();
            },
            onHorizontalDragUpdate: (details) {
              if (_isLocked || _isLongPressSpeeding || !_isDraggingProgress) {
                return;
              }
              final durationSeconds = _duration.inSeconds.toDouble();
              final offsetSeconds = details.primaryDelta! * 0.8;
              setState(() {
                _dragTargetSeconds = (_dragTargetSeconds + offsetSeconds).clamp(
                  0.0,
                  durationSeconds > 0 ? durationSeconds : 1.0,
                );
              });
              final targetDur = Duration(seconds: _dragTargetSeconds.toInt());
              final diff = (targetDur.inSeconds - _position.inSeconds);
              final diffStr = diff >= 0 ? '+$diff秒' : '$diff秒';
              _showHudMessage(
                '$diffStr (${_formatDuration(targetDur)} / ${_formatDuration(_duration)})',
                BIcons.fastForward,
              );
            },
            onHorizontalDragEnd: (details) {
              if (_isLocked) return;
              if (_isDraggingProgress) {
                _isDraggingProgress = false;
                _seekWithSync(Duration(seconds: _dragTargetSeconds.toInt()));
                _resetHideControlsTimer();
              }
            },
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 视频解码渲染层 (支持居中自适应 / 16:9 / 4:3 / 铺满 + 极光画质增强)
                    _buildVideoSurface(),

                    Positioned.fill(
                      child: DanmakuOverlay(
                        items: _danmaku,
                        episodeKey: _episodeKey(),
                        position: _isDraggingProgress
                            ? Duration(
                                milliseconds: (_dragTargetSeconds * 1000)
                                    .round(),
                              )
                            : _position,
                        enabled: _appState.danmakuEnabled,
                        playing: _isPlaying && !_isDraggingProgress,
                        opacity: _appState.danmakuOpacity,
                        fontScale: _appState.danmakuFontScale,
                        speed: _appState.danmakuSpeed,
                        area: _appState.danmakuArea,
                        blocked: _appState.danmakuBlockedWords,
                      ),
                    ),

                    // 软调亮度遮罩
                    if (_brightness < 1.0)
                      Container(
                        color: Colors.black.withValues(
                          alpha: 1.0 - _brightness,
                        ),
                      ),

                    // 双击快进快退反馈浮层
                    if (_showQuickSeekTip)
                      BrandPlayerHUD(
                        icon: _quickSeekTip.startsWith('+')
                            ? BIcons.fastForward
                            : BIcons.rewind,
                        text: _quickSeekTip,
                      ),

                    // HUD 浮层 (音量/亮度/滑动定位)
                    if (_showHud && !_showQuickSeekTip)
                      BrandPlayerHUD(icon: _hudIcon, text: _hudText),

                    if (_isBuffering && !_hasError)
                      const Center(child: BrandIntro(width: 300, onDark: true)),

                    // 错误浮层
                    if (_hasError)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          margin: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B)
                                .withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.rose.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const BrandIcon(
                                BIcons.alert,
                                color: AppColors.rose,
                                size: 40,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        _loadAndPlayCurrentEpisode(),
                                    icon: const BrandIcon(
                                      BIcons.refresh,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      '重试播放',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary600,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 自动连播下一集倒计时浮层
                    if (_isAutoPlayingNext)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primary500.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$_nextCountdownSeconds 秒后自动播放下一集',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton(
                                    onPressed: _cancelAutoPlayNext,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.35,
                                        ),
                                        width: 1.0,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    child: const Text(
                                      '取消连播',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: () {
                                      _cancelAutoPlayNext();
                                      _playNextEpisode();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary600,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    child: const Text(
                                      '立即切集',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 长按加速指示器 (居中偏上)
                    if (_isLongPressSpeeding)
                      Positioned(
                        top: isCompact ? 16 : 28,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: BrandPlayerSpeedBoostBadge(
                            speed: _boostSpeed,
                            isCompact: isCompact,
                          ),
                        ),
                      ),

                    // 控制蒙层 (顶部 + 底部 + 居中 + 锁屏)
                    if (_showControls && !_isLongPressSpeeding)
                      _buildControlsOverlay(currentEp, currentGroup, groups),

                    // 播放器内嵌倍速调节悬浮面板 (非全屏弹窗，0.5x-4.0x 滑块)
                    if (_showSpeedPanel && !_isLocked)
                      Align(
                        alignment: isCompact
                            ? Alignment.center
                            : Alignment.bottomRight,
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: isCompact ? 0 : 20,
                            bottom: isCompact ? 0 : 70,
                          ),
                          child: BrandPlayerSpeedPanel(
                            currentSpeed: _currentSpeed,
                            isCompact: isCompact,
                            onSpeedChanged: _setSpeed,
                            onClose: () {
                              setState(() {
                                _showSpeedPanel = false;
                              });
                              _resetHideControlsTimer();
                            },
                          ),
                        ),
                      ),

                    // 全屏模式下的内嵌选集抽屉
                    if (_isFullscreen && _showFullscreenDrawer)
                      _buildFullscreenDrawer(groups),

                    // 鼠标移动即唤出控制层（桌面标准行为）：
                    // 控制层淡出后标题栏/拖拽区随之消失，用户无从下手
                    Positioned.fill(
                      child: MouseRegion(
                        opaque: false,
                        onHover: (_) {
                          if (!_showControls) {
                            setState(() => _showControls = true);
                          }
                          _resetHideControlsTimer();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (_isFullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _toggleFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: playerCore),
        ),
      );
    }

    final isDesktop = Responsive.isDesktop(context);

    if (isDesktop) {
      // 桌面版式（规格版）：
      // 状态A（首屏）：全宽 16:9 播放器（毛玻璃控制层，静止 3s 自动淡出）+ 信息区
      //               + 右栏 Tab 面板（选集 / AI 剧情助手 / 一起看）
      // 状态B（滚动）：播放器转右下角 280px 悬浮小窗，左栏纵向信息流铺开，
      //               右栏随页面自然滚走（不再 sticky）
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFf8fafc),
        body: Stack(
          children: [
            // 左栏滚动流（为固定悬浮的右栏让出宽度）
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _pageScroll,
                padding: EdgeInsets.only(
                  top: kBrandAppBarTopInset,
                  right: 404,
                  bottom: 48,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPlayerStage(isDark, playerCore),
                        const SizedBox(height: 14),
                        _buildInfoSection(isDark),
                        const SizedBox(height: 16),
                        ..._buildFeed(isDark),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 右栏：固定悬浮，不随滚动（选集 / AI 助手 / 一起看 常驻可用）
            Positioned(
              top: kBrandAppBarTopInset + 8,
              right: 16,
              bottom: 16,
              width: 372,
              child: _buildSideRail(isDark, currentGroup),
            ),
            // 状态B：悬浮小窗
            if (_miniFloat) _buildMiniPlayer(isDark),
          ],
        ),
      );
    }

    // 移动端：播放器满宽 16:9 贴顶；矮窗（横屏）时压缩视频高度，
    // 保证下方选项卡与内容区最少 260px 可操作。
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF7F8FB),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const tabsH = 47.0;
            final idealVideoH = constraints.maxWidth * 9 / 16;
            final maxVideoH = (constraints.maxHeight - tabsH - 260)
                .clamp(160.0, double.infinity)
                .toDouble();
            final videoH = idealVideoH > maxVideoH ? maxVideoH : idealVideoH;
            return Column(
              children: [
                SizedBox(height: videoH, child: playerCore),
                _sheetTabs(isDark),
                Expanded(
                  child: IndexedStack(
                    index: _sheetIndex,
                    sizing: StackFit.expand,
                    children: [
                      _videoSheet(isDark, currentEp, currentGroup),
                      _danmakuSheet(isDark),
                      _watchSheet(isDark),
                      _commentSheet(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ================= 桌面新版页面（规格版） =================

  /// 滚动监听：播放器滚出视口进入状态B（悬浮小窗，原槽位收起并补偿滚动位置，
  /// 视口内容无感）；向上滚回顶部区域或点小窗则归位还原。
  void _syncMiniState() {
    if (!mounted || _isFullscreen || !Responsive.isDesktop(context)) return;
    final o = _pageScroll.hasClients ? _pageScroll.offset : 0.0;
    if (_isFullscreen) {
      _exitMini(compensate: true);
      return;
    }
    if (_miniFloat) {
      // 悬浮中坐标系已补偿：接近顶部区域 → 归位还原（槽位恢复，视口自然回到播放器）
      if (o <= 40) setState(() => _miniFloat = false);
    } else if (!_miniDismissed && o > _lastPlayerH + 40) {
      // 播放器完全滚出视口 → 进入悬浮模式。
      // 先标记再补偿（jumpTo 的通知里 _miniFloat 已为 true，避免重入重复扣减）
      setState(() => _miniFloat = true);
      _pageScroll.jumpTo((o - _lastPlayerH).clamp(0.0, double.infinity));
    }
    if (!_miniFloat && _miniDismissed && o <= 2) {
      // 关闭过悬浮窗后滚回顶部：恢复自动悬浮能力
      setState(() => _miniDismissed = false);
    }
  }

  /// 退出悬浮模式。compensate=true 时恢复槽位并补偿滚动位置（保持视口内容不变），
  /// 用于关闭悬浮窗/进入全屏等"播放器回到文档流中部"的场景。
  void _exitMini({bool compensate = false}) {
    if (compensate && _pageScroll.hasClients) {
      _pageScroll.jumpTo(
        (_pageScroll.offset + _lastPlayerH).clamp(0.0, double.infinity),
      );
    }
    if (mounted && _miniFloat) setState(() => _miniFloat = false);
  }

  Future<void> _loadWiki() async {
    try {
      final result = await ApiService().getVideoDetail(widget.video.id);
      final wiki = result['wiki'] as WikiSubject?;
      if (!mounted || wiki == null) return;
      setState(() => _wiki = wiki);
    } catch (_) {}
  }

  /// 播放器舞台：容器宽度决定 16:9 高度（首屏与右栏等高）
  Widget _buildPlayerStage(bool isDark, Widget core) {
    if (_miniFloat || _miniDismissed) {
      // 状态B：播放器脱离文档流（悬浮小窗接管），信息流向上顶替
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = (constraints.maxWidth * 9 / 16).clamp(300.0, 780.0);
        _lastPlayerH = h;
        return SizedBox(
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: core,
          ),
        );
      },
    );
  }

  /// 播放器下方信息区：标题 + 操作组 + UP 行 + 简介 + 标签
  Widget _buildInfoSection(bool isDark) {
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final card = isDark ? AppColors.darkCard : Colors.white;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFe2e8f0);
    final synopsis = widget.video.content.trim();
    final upName = widget.video.subName.isNotEmpty
        ? widget.video.subName
        : 'bllii 放映室';
    final meta = [
      if (widget.video.year.isNotEmpty) '发布于 ${widget.video.year}',
      if (widget.video.hits > 0)
        '${formatAudienceCount(widget.video.hits)} 次播放',
      '${_danmaku.length} 弹幕',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 + 操作组
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.video.name,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _infoActions(isDark),
            ],
          ),
          const SizedBox(height: 14),
          // UP 主信息行
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF89C7),
                      Color(0xFFAE8CFF),
                      Color(0xFF80B6FF),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: const Center(
                  child: BrandIcon(BIcons.play, size: 18, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            upName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _followButton(isDark),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(meta, style: TextStyle(fontSize: 11.5, color: muted)),
                  ],
                ),
              ),
            ],
          ),
          if (synopsis.isNotEmpty) ...[
            const SizedBox(height: 12),
            // 简介：默认 2 行 + 展开/收起
            GestureDetector(
              onTap: () => setState(() => _synopsisOpen = !_synopsisOpen),
              behavior: HitTestBehavior.opaque,
              child: Text(
                synopsis,
                maxLines: _synopsisOpen ? null : 2,
                overflow: _synopsisOpen
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.65, color: muted),
              ),
            ),
            if (synopsis.length > 66)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      setState(() => _synopsisOpen = !_synopsisOpen),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    _synopsisOpen ? '收起' : '展开',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary500,
                    ),
                  ),
                ),
              ),
          ],
          // 标签组
          if (widget.video.tags.isNotEmpty ||
              widget.video.typeName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in [widget.video.typeName, ...widget.video.tags])
                  if (tag.trim().isNotEmpty) _tagChip(tag.trim(), isDark),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 标题右侧操作组：点赞 / 收藏 / 投币 / 转发 / 下载
  Widget _infoActions(bool isDark) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    Widget action({
      required BrandIconData icon,
      required String label,
      Color? color,
      VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandIcon(
                icon,
                size: 19,
                color: color ?? muted,
                monochrome: color == null,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color ?? muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(
          icon: BIcons.heart,
          label: _liked ? '已赞' : '点赞',
          color: _liked ? const Color(0xFFF43F5E) : null,
          onTap: () => setState(() {
            _liked = !_liked;
            _showTopToast(_liked ? '已点赞' : '已取消点赞');
          }),
        ),
        action(
          icon: BIcons.star,
          label: _favorite ? '已收藏' : '收藏',
          color: _favorite ? const Color(0xFFFFB020) : null,
          onTap: _savingFavorite ? null : _toggleFavorite,
        ),
        action(
          icon: BIcons.plus,
          label: '投币',
          onTap: () => _showTopToast('投币功能即将上线'),
        ),
        action(icon: BIcons.share, label: '转发', onTap: _showShareDialog),
        action(
          icon: BIcons.download,
          label: '下载',
          onTap: () => _showTopToast('暂不支持缓存下载，请在线观看'),
        ),
      ],
    );
  }

  Widget _followButton(bool isDark) {
    return InkWell(
      onTap: () =>
          _showTopToast(_appState.isLoggedIn ? '已关注，更新会第一时间提醒' : '登录后即可关注'),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary600.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandIcon(BIcons.plus, size: 12, color: AppColors.primary500),
            const SizedBox(width: 3),
            const Text(
              '关注',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(String text, bool isDark) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return InkWell(
      onTap: () => _showTopToast('标签：$text'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '# $text',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
      ),
    );
  }

  /// 右栏 Tab 面板：选集 / AI 剧情助手 / 一起看（首屏与播放器同高）
  Widget _buildSideRail(bool isDark, PlayGroup? currentGroup) {
    final card = isDark ? AppColors.darkCard : Colors.white;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFe2e8f0);
    final labels = ['选集', 'AI 助手', '一起看'];
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
                    child: _railTab(
                      labels[i],
                      active: _sideTab == i,
                      isDark: isDark,
                      onTap: () => setState(() => _sideTab = i),
                    ),
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : const Color(0xFFe2e8f0),
          ),
          Expanded(
            child: IndexedStack(
              index: _sideTab,
              children: [
                _episodePanel(isDark, currentGroup),
                _aiPanel(isDark),
                _watchSheet(isDark),
              ],
            ),
          ),
          // 底部：相关推荐（两两往下排列，权重后置）
          if (_related.isNotEmpty)
            SizedBox(height: 248, child: _railRelated(isDark)),
        ],
      ),
    );
  }

  /// 相关推荐：两两往下排列
  Widget _railRelated(bool isDark) {
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : const Color(0xFFe2e8f0),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '相关推荐',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: _related.length,
              itemBuilder: (context, i) {
                final item = _related[i];
                return InkWell(
                  onTap: () => _openRelated(item),
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: double.infinity,
                            child: item.picture.isEmpty
                                ? ColoredBox(
                                    color: isDark
                                        ? AppColors.darkBg
                                        : const Color(0xFFE2E8F0),
                                  )
                                : Image.network(
                                    item.picture,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: ink),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _railTab(
    String label, {
    required bool active,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Material(
      color: active
          ? AppColors.primary600.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? AppColors.primary500 : muted,
            ),
          ),
        ),
      ),
    );
  }

  /// Tab1：集数搜索 + 分集列表（当前集高亮 + 播放图标）+ 底部相关推荐
  Widget _episodePanel(bool isDark, PlayGroup? currentGroup) {
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final groups = widget.video.playGroups;
    final episodes = currentGroup?.episodes ?? const <Episode>[];
    final query = _episodeSearch.text.trim();
    final shown = <int>[];
    for (var i = 0; i < episodes.length; i++) {
      final name = episodes[i].name;
      if (query.isEmpty || name.contains(query) || '${i + 1}'.contains(query)) {
        shown.add(i);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 集数搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            controller: _episodeSearch,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 12.5, color: ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索集数 / 输入编号',
              hintStyle: TextStyle(fontSize: 12, color: muted),
              prefixIcon: BrandIcon(
                BIcons.search,
                size: 16,
                color: muted,
                monochrome: true,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              filled: true,
              fillColor: isDark ? AppColors.darkBg : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFe2e8f0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFe2e8f0),
                ),
              ),
            ),
          ),
        ),
        // 线路（多于一条时）
        if (groups.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < groups.length; i++)
                  _railTab(
                    groups[i].server.isNotEmpty
                        ? groups[i].server
                        : '线路${i + 1}',
                    active: i == _currentGroupIndex,
                    isDark: isDark,
                    onTap: () => _switchEpisode(i, 0),
                  ),
              ],
            ),
          ),
        // 分集列表
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配的集数',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  itemCount: shown.length,
                  itemBuilder: (context, idx) {
                    final i = shown[idx];
                    final ep = episodes[i];
                    final current = i == _currentEpisodeIndex;
                    return InkWell(
                      onTap: () => _switchEpisode(_currentGroupIndex, i),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: current
                              ? AppColors.primary600.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            if (current)
                              const BrandIcon(
                                BIcons.play,
                                size: 13,
                                color: AppColors.primary500,
                              )
                            else
                              SizedBox(
                                width: 13,
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ep.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: current
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: current ? AppColors.primary500 : ink,
                                ),
                              ),
                            ),
                            if (current)
                              Text(
                                '播放中',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Tab2：AI 剧情助手（迷你时间轴 + 实时角色卡片 + 解读文本）
  Widget _aiPanel(bool isDark) {
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final hasDuration = _duration.inMilliseconds > 0;
    final relations = _wiki?.forwardRelations ?? const [];
    final cast = relations
        .where(
          (r) =>
              r.relationType == 'character_play' || r.relationType == 'actor',
        )
        .toList();
    final highlight = _currentHighlight();
    final summary = (_wiki?.summary.isNotEmpty == true)
        ? _wiki!.summary
        : (widget.video.content.isEmpty ? '加载剧情资料中…' : widget.video.content);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 迷你横向时间轴（拖拽跳转，与播放进度双向联动）
        Text(
          '播放进度',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        Row(
          children: [
            Text(
              _formatDuration(_position),
              style: TextStyle(
                fontSize: 10.5,
                color: muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                  overlayColor: AppColors.primary500.withValues(alpha: 0.15),
                  activeTrackColor: AppColors.primary500,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                ),
                child: Slider(
                  value: hasDuration
                      ? _position.inMilliseconds
                            .clamp(0, _duration.inMilliseconds)
                            .toDouble()
                      : 0,
                  max: hasDuration ? _duration.inMilliseconds.toDouble() : 1,
                  onChanged: hasDuration && !_watchGuestLocked()
                      ? (v) => _seekWithSync(Duration(milliseconds: v.toInt()))
                      : null,
                ),
              ),
            ),
            Text(
              _formatDuration(_duration),
              style: TextStyle(
                fontSize: 10.5,
                color: muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 实时角色卡片
        Text(
          '出场角色',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        if (cast.isEmpty)
          Text('暂无角色资料', style: TextStyle(fontSize: 12, color: muted))
        else
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final r = cast[i];
                final subject = r.targetSubject;
                final name = subject?.name ?? r.roleDescription;
                final role = WikiSubject.relationLabel(r.relationType);
                return Container(
                  width: 128,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBg : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFe2e8f0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        // 实时解读文本
        Text(
          '实时解读',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBg : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (highlight != null) ...[
                Row(
                  children: [
                    BrandIcon(BIcons.sparkles, size: 12, color: AppColors.gold),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '本段看点 · ${_formatDuration(Duration(milliseconds: highlight.key))}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  highlight.value,
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: muted),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                summary,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, height: 1.6, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => showRagAskSheet(
            context,
            seedQuestion:
                '${widget.video.name} 第${_currentEpisodeIndex + 1}集讲了什么？',
          ),
          icon: BrandIcon(
            BIcons.sparkles,
            size: 15,
            color: AppColors.primary500,
          ),
          label: const Text('向 AI 问答剧情'),
        ),
      ],
    );
  }

  /// 左栏纵向信息流：AI 深度解读 → 精选时间弹幕 → 评论区 → 相关推荐
  List<Widget> _buildFeed(bool isDark) {
    const gap = SizedBox(height: 16);
    return [
      _aiDeepCard(isDark),
      gap,
      _featuredDanmakuCard(isDark),
      gap,
      _commentCard(isDark),
      gap,
      _relatedFeedCard(isDark),
    ];
  }

  Widget _feedShell(
    bool isDark,
    String title,
    BrandIconData icon, {
    required Widget child,
    Widget? trailing,
  }) {
    final card = isDark ? AppColors.darkCard : Colors.white;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFe2e8f0);
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BrandIcon(icon, size: 16, color: AppColors.primary500),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// AI 深度解读大卡片：剧情摘要 + 角色关系 + 看点（伏笔）汇总
  Widget _aiDeepCard(bool isDark) {
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final wiki = _wiki;
    final relations = wiki?.forwardRelations ?? const [];
    final highlights = _danmakuHighlights();
    final summary = (wiki?.summary.isNotEmpty == true)
        ? wiki!.summary
        : widget.video.content.trim();

    return _feedShell(
      isDark,
      'AI 深度解读',
      BIcons.sparkles,
      trailing: InkWell(
        onTap: () => showRagAskSheet(
          context,
          seedQuestion: '${widget.video.name} 有哪些值得注意的伏笔？',
        ),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary600.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '问 AI',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary500,
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.isEmpty ? '暂无剧情资料' : summary,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, height: 1.7, color: muted),
          ),
          const SizedBox(height: 14),
          Text(
            '角色关系',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          if (relations.isEmpty)
            Text('暂无角色关系数据', style: TextStyle(fontSize: 12, color: muted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in relations.take(10))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkBg
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : const Color(0xFFe2e8f0),
                      ),
                    ),
                    child: Text(
                      '${r.sourceSubject?.name ?? '本作'}'
                      ' —${WikiSubject.relationLabel(r.relationType)}→ '
                      '${r.targetSubject?.name ?? r.roleDescription}',
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          Text(
            '伏笔与看点汇总',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          if (highlights.isEmpty)
            Text(
              '这一集还没有足够的弹幕生成看点',
              style: TextStyle(fontSize: 12, color: muted),
            )
          else
            Column(
              children: [
                for (final h in highlights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDuration(Duration(milliseconds: h.key)),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            h.value,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// 精选时间弹幕：点击跳转对应时间
  Widget _featuredDanmakuCard(bool isDark) {
    final highlights = _danmakuHighlights();
    if (highlights.isEmpty) return const SizedBox.shrink();
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    return _feedShell(
      isDark,
      '精选时间弹幕',
      BIcons.message,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final h in highlights)
            InkWell(
              onTap: () {
                if (_watchGuestLocked()) return;
                _seekWithSync(Duration(milliseconds: h.key));
                _showTopToast(
                  '跳转到 ${_formatDuration(Duration(milliseconds: h.key))}',
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBg : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : const Color(0xFFe2e8f0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatDuration(Duration(milliseconds: h.key)),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        h.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _commentCard(bool isDark) {
    // VideoCommentSection 自带卡片/标题/输入框/空态，不再套外层边框；
    // 无评论时收紧高度避免大段空白，有评论时给足浏览空间
    return SizedBox(
      height: _commentTotal > 0 ? 620 : 224,
      child: VideoCommentSection(
        targetId: widget.video.id,
        onTotal: (total) {
          if (_commentTotal == total) return;
          setState(() => _commentTotal = total);
        },
      ),
    );
  }

  Widget _relatedFeedCard(bool isDark) {
    if (_related.isEmpty) return const SizedBox.shrink();
    return _feedShell(
      isDark,
      '相关推荐',
      BIcons.compass,
      child: SizedBox(
        height: 216,
        child: DesktopHorizontalScroll(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _related.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = _related[index];
              return AudiencePosterTile(
                video: item,
                onTap: () => _openRelated(item),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 弹幕密度看点：按时长分桶，取每桶最长的一条弹幕作为该段代表
  List<MapEntry<int, String>> _danmakuHighlights() {
    if (_danmaku.isEmpty || _duration.inMilliseconds <= 0) {
      return const [];
    }
    final total = _duration.inMilliseconds;
    const bins = 10;
    final picked = <MapEntry<int, String>>[];
    for (var b = 0; b < bins; b++) {
      final from = total * b ~/ bins;
      final to = total * (b + 1) ~/ bins;
      MapEntry<int, String>? best;
      for (final d in _danmaku) {
        if (d.playTimeMs < from || d.playTimeMs >= to) continue;
        if (d.content.trim().length < 2) continue;
        if (best == null || d.content.length > best.value.length) {
          best = MapEntry(d.playTimeMs, d.content.trim());
        }
      }
      if (best != null) {
        picked.add(
          MapEntry(
            best.key,
            best.value.length > 16
                ? '${best.value.substring(0, 16)}…'
                : best.value,
          ),
        );
      }
    }
    return picked;
  }

  String? _bubbleLabelFor(double ms) {
    for (final h in _danmakuHighlights()) {
      if ((h.key - ms).abs() < _duration.inMilliseconds * 0.02) return h.value;
    }
    return null;
  }

  MapEntry<int, String>? _currentHighlight() {
    final highlights = _danmakuHighlights();
    if (highlights.isEmpty) return null;
    MapEntry<int, String>? nearest;
    for (final h in highlights) {
      if (nearest == null ||
          (h.key - _position.inMilliseconds).abs() <
              (nearest.key - _position.inMilliseconds).abs()) {
        nearest = h;
      }
    }
    return nearest;
  }

  /// 更多菜单（底部控制栏）
  List<PopupMenuEntry<String>> _moreMenuItems(List<PlayGroup> groups) {
    return [
      if (groups.length > 1) ...[
        const PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '切换线路',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ),
        for (var i = 0; i < groups.length; i++)
          PopupMenuItem<String>(
            value: 'route:$i',
            child: Text(
              groups[i].server.isNotEmpty ? groups[i].server : '线路${i + 1}',
              style: TextStyle(
                fontSize: 12.5,
                color: i == _currentGroupIndex ? AppColors.primary400 : null,
                fontWeight: i == _currentGroupIndex ? FontWeight.w700 : null,
              ),
            ),
          ),
        const PopupMenuDivider(),
      ],
      const PopupMenuItem<String>(
        value: 'chapters',
        child: Text(
          '章节时间线',
          style: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'danmaku',
        child: Text(
          '发弹幕',
          style: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      PopupMenuItem<String>(
        value: 'enhance',
        child: Text(
          _isEnhanced ? '关闭极光画质增强' : '开启极光画质增强',
          style: const TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      PopupMenuItem<String>(
        value: 'aspect',
        child: Text(
          '画面比例：${_aspectModeLabel(_aspectMode)}',
          style: const TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'share',
        child: Text(
          '分享本片',
          style: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'cast',
        child: Text(
          '投屏到电视',
          style: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
    ];
  }

  void _onMoreSelected(String value) {
    if (value.startsWith('route:')) {
      final idx = int.tryParse(value.split(':')[1]) ?? 0;
      _switchEpisode(idx, 0);
      return;
    }
    switch (value) {
      case 'chapters':
        _showChapterTimeline();
      case 'danmaku':
        _composeDanmaku();
      case 'enhance':
        _toggleEnhance();
      case 'aspect':
        _toggleAspectMode();
      case 'share':
        _showShareDialog();
      case 'cast':
        _showTopToast('投屏功能即将上线');
    }
  }

  /// 章节时间线弹窗（居中宽幅横向时间线，标记取自弹幕密度看点）
  Future<void> _showChapterTimeline() async {
    if (_duration.inMilliseconds <= 0) {
      _showTopToast('暂无进度信息');
      return;
    }
    final highlights = _danmakuHighlights();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF16213A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            '章节时间线',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 760,
            child: highlights.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '这一集还没有足够的弹幕生成章节看点',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  )
                : SizedBox(
                    height: 110,
                    child: LayoutBuilder(
                      builder: (context, cons) {
                        final w = cons.maxWidth;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 62,
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            Positioned(
                              left:
                                  (_position.inMilliseconds /
                                          _duration.inMilliseconds)
                                      .clamp(0.0, 1.0) *
                                  (w - 20),
                              top: 56,
                              child: Container(
                                width: 4,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: AppColors.primary400,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            for (final h in highlights)
                              Positioned(
                                left:
                                    (h.key / _duration.inMilliseconds).clamp(
                                      0.0,
                                      1.0,
                                    ) *
                                    (w - 20),
                                top: 0,
                                width: 130,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    if (!_watchGuestLocked()) {
                                      _seekWithSync(
                                        Duration(milliseconds: h.key),
                                      );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatDuration(
                                          Duration(milliseconds: h.key),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primary400,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        h.value,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primary400,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  /// 分享弹窗：复制链接
  Future<void> _showShareDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    var link = '${_appState.apiBaseUrl}/play/${widget.video.id}';
    link += '?ep=$_currentEpisodeIndex';
    if (_currentGroupIndex > 0) link += '&route=$_currentGroupIndex';
    await showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: link);
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF16213A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            '分享给同好',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.video.name} · 第${_currentEpisodeIndex + 1}话',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                readOnly: true,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkBg
                      : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (!context.mounted) return;
                Navigator.of(context).pop();
                _showTopToast('链接已复制');
              },
              icon: const BrandIcon(BIcons.link, size: 15, color: Colors.white),
              label: const Text('复制链接'),
            ),
          ],
        );
      },
    );
  }

  /// 右上角轻提示 Toast
  void _showTopToast(String message) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: kBrandAppBarTopInset + 56,
        right: 28,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * -10),
                child: child,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Timer(const Duration(milliseconds: 1900), () {
      if (entry.mounted) entry.remove();
    });
  }

  /// 画布内滚轮调节音量（通过 PointerSignalResolver 独占，页面不滚动）
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (event is! PointerScrollEvent) return;
      if (_isLocked) return;
      final delta = event.scrollDelta.dy;
      if (delta == 0) return;
      final v = (_volume - delta / 10).clamp(0.0, 100.0);
      setState(() => _volume = v);
      _player.setVolume(v);
      _showHudMessage(
        '音量: ${v.round()}%',
        v == 0 ? BIcons.muted : BIcons.volume,
      );
    });
  }

  void _setDockVolume(double v) {
    setState(() => _volume = v);
    _player.setVolume(v);
  }

  /// 状态B：右下角 280px 悬浮小窗（拖拽限定右下区域；点击还原；关闭即暂停）
  Widget _buildMiniPlayer(bool isDark) {
    final size = MediaQuery.sizeOf(context);
    final right = (18 - _miniDrag.dx).clamp(8.0, size.width * 0.55).toDouble();
    final bottom = (18 - _miniDrag.dy).clamp(8.0, size.height * 0.6).toDouble();
    final glass = isDark
        ? const Color(0xFF16213A).withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.92);
    return Positioned(
      right: right,
      bottom: bottom,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        builder: (_, t, child) => Transform.scale(
          scale: t,
          alignment: Alignment.bottomRight,
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            decoration: BoxDecoration(
              color: glass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 视频画面（同一 VideoController 的第二表面）：点击回顶还原
                GestureDetector(
                  onTap: _restoreFromMini,
                  child: SizedBox(
                    height: 157.5,
                    child: Video(
                      controller: _videoController,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  color: Colors.black.withValues(alpha: 0.25),
                  child: Row(
                    children: [
                      // 拖拽抓手（限定右下区域移动）
                      GestureDetector(
                        onPanUpdate: (d) => setState(() {
                          _miniDrag += Offset(d.delta.dx, -d.delta.dy);
                        }),
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: BrandIcon(
                            BIcons.library,
                            size: 16,
                            color: Colors.white54,
                            monochrome: true,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _miniCtl(
                        icon: _isPlaying ? BIcons.pause : BIcons.play,
                        tooltip: _isPlaying ? '暂停' : '播放',
                        onTap: _togglePlayPause,
                      ),
                      _miniCtl(
                        icon: BIcons.arrowUp,
                        tooltip: '回到顶部还原',
                        onTap: _restoreFromMini,
                      ),
                      _miniCtl(
                        icon: BIcons.close,
                        tooltip: '关闭悬浮窗（暂停播放）',
                        onTap: _closeMini,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniCtl({
    required BrandIconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: BrandIcon(icon, size: 16, color: Colors.white, monochrome: true),
    );
  }

  void _restoreFromMini() {
    if (mounted) setState(() => _miniFloat = false); // 槽位恢复，播放器回到文档流
    _pageScroll.animateTo(
      0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _closeMini() {
    _player.pause();
    _exitMini(compensate: true);
    if (mounted) setState(() => _miniDismissed = true);
  }

  /// 一起看面板（房间 / 聊天）。
  Widget _watchSheet(bool isDark) {
    return WatchTogetherPanel(
      watch: _watch,
      isDark: isDark,
      loggedIn: _appState.isLoggedIn,
      videoId: widget.video.id,
      videoName: widget.video.name,
      currentGroupIndex: () => _currentGroupIndex,
      currentEpisodeIndex: () => _currentEpisodeIndex,
      currentEpisodeName: () {
        final groups = widget.video.playGroups;
        if (_currentGroupIndex < groups.length &&
            _currentEpisodeIndex < groups[_currentGroupIndex].episodes.length) {
          return groups[_currentGroupIndex].episodes[_currentEpisodeIndex].name;
        }
        return '';
      },
    );
  }

  /// 胶囊分段选项卡：激活项品牌渐变高亮，弹幕/评论带计数，一起看在房时带直播点。
  Widget _sheetTabs(bool isDark) {
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final entries = <(String, int?, bool)>[
      ('视频', null, false),
      ('弹幕', _danmaku.isEmpty ? null : _danmaku.length, false),
      ('一起看', null, _watch.active),
      ('评论', _commentTotal > 0 ? _commentTotal : null, false),
    ];
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : Colors.white,
        border: Border(bottom: BorderSide(color: border, width: 0.8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (var index = 0; index < entries.length; index++)
            Expanded(
              child: Center(
                child: _sheetTabPill(
                  isDark: isDark,
                  label: entries[index].$1,
                  count: entries[index].$2,
                  live: entries[index].$3,
                  active: _sheetIndex == index,
                  onTap: () => setState(() => _sheetIndex = index),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sheetTabPill({
    required bool isDark,
    required String label,
    required int? count,
    required bool live,
    required bool active,
    required VoidCallback onTap,
  }) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final idleBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF1F5F9);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [
                      Color(0xFFFF89C7),
                      Color(0xFFAE8CFF),
                      Color(0xFF80B6FF),
                    ],
                  )
                : null,
            color: active ? null : idleBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live && !active) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF43F5E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? Colors.white : muted,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: 0.22)
                        : muted.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count > 999 ? '999+' : '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoSheet(
    bool isDark,
    Episode? currentEp,
    PlayGroup? currentGroup, {
    bool embedEpisodes = true,
    bool showHeader = true,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _danmakuBar(isDark),
        if (showHeader) ...[
          const SizedBox(height: 14),
          _titleBlock(isDark, currentEp, currentGroup),
          const SizedBox(height: 16),
          _actionRow(isDark),
        ],
        if (embedEpisodes) ...[
          const SizedBox(height: 18),
          _episodeHeading(isDark, currentGroup),
          const SizedBox(height: 8),
          _episodeCards(),
        ],
        if (!embedEpisodes) ...[
          const SizedBox(height: 16),
          _buildDesktopMetaCard(isDark),
          _buildDesktopShortcutGuide(isDark),
        ],
        if (_related.isNotEmpty) ...[
          const SizedBox(height: 18),
          _relatedHeading(isDark),
          const SizedBox(height: 12),
          SizedBox(
            height: 196,
            child: DesktopHorizontalScroll(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _related.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = _related[index];
                  return AudiencePosterTile(
                    video: item,
                    onTap: () => _openRelated(item),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _episodeKey() {
    final groups = widget.video.playGroups;
    if (groups.isEmpty || _currentGroupIndex >= groups.length) return '0';
    final group = groups[_currentGroupIndex];
    if (_currentEpisodeIndex >= group.episodes.length) {
      return '$_currentGroupIndex';
    }
    final name = group.episodes[_currentEpisodeIndex].name.trim();
    final key = '$_currentGroupIndex:$name';
    final runes = key.runes.toList();
    if (runes.length <= 80) return key;
    return String.fromCharCodes(runes.take(80));
  }

  Future<void> _loadDanmaku() async {
    final key = _episodeKey();
    final generation = ++_danmakuGeneration;
    try {
      final raw = await ApiService().listDanmaku(
        videoId: widget.video.id,
        episodeKey: key,
      );
      if (!mounted ||
          generation != _danmakuGeneration ||
          key != _episodeKey()) {
        return;
      }
      setState(() {
        _danmaku = raw.map(DanmakuItem.fromJson).toList();
      });
    } catch (_) {
      if (!mounted || generation != _danmakuGeneration) return;
      setState(() => _danmaku = []);
    }
  }

  Future<void> _composeDanmaku() async {
    if (!_appState.isLoggedIn) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AccountScreen()));
      if (!mounted || !_appState.isLoggedIn) return;
    }
    final draft = await showDanmakuComposer(context);
    if (draft == null || !mounted || _sendingDanmaku) return;
    setState(() => _sendingDanmaku = true);
    try {
      final created = await ApiService().sendDanmaku(
        videoId: widget.video.id,
        episodeKey: _episodeKey(),
        playTimeMs: _position.inMilliseconds,
        mode: draft.mode,
        color: draft.color,
        content: draft.text,
      );
      if (!mounted) return;
      setState(() => _danmaku = [..._danmaku, DanmakuItem.fromJson(created)]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _sendingDanmaku = false);
    }
  }

  Future<void> _removeDanmaku(DanmakuItem item) async {
    final mine = _appState.user?['id']?.toString() == '${item.userId}';
    if (!mine) return;
    try {
      await ApiService().deleteDanmaku(item.id);
      if (!mounted) return;
      setState(
        () =>
            _danmaku = _danmaku.where((entry) => entry.id != item.id).toList(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _danmakuBar(bool isDark) {
    final fill = isDark ? AppColors.darkCard : const Color(0xFFF3F4F8);
    final enabled = _appState.danmakuEnabled;
    return Row(
      children: [
        Text(
          '弹幕',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
          ),
        ),
        Transform.scale(
          scale: .8,
          child: Switch.adaptive(
            value: enabled,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary500,
            onChanged: (value) {
              _appState.setDanmakuEnabled(value);
              setState(() {});
            },
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _sendingDanmaku ? null : _composeDanmaku,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _sendingDanmaku ? '发送中…' : '点我发弹幕～',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleBlock(bool isDark, Episode? currentEp, PlayGroup? currentGroup) {
    final count = currentGroup?.episodes.length ?? 0;
    final update = [
      widget.video.remarks,
      if (count > 0) '全$count话',
    ].where((item) => item.isNotEmpty).join(' · ');
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.video.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: ink,
                ),
              ),
            ),
            if (widget.video.hits > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A34).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandIcon(
                      BIcons.flame,
                      size: 14,
                      color: Color(0xFFFF8A34),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${formatAudienceCount(widget.video.hits)}人气',
                      style: const TextStyle(
                        color: Color(0xFFFF8A34),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (currentEp != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary500.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandIcon(
                      BIcons.playCircle,
                      size: 12,
                      color: AppColors.primary500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      currentEp.name,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (update.isNotEmpty)
              Expanded(
                child: Text(
                  update,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _actionRow(bool isDark) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _actionItem(
            icon: BIcons.thumbUp,
            label: widget.video.hits > 0
                ? formatAudienceCount(widget.video.hits)
                : '点赞',
            color: muted,
          ),
          _actionItem(
            icon: _favorite ? BIcons.star : BIcons.star,
            label: _favorite ? '已追番' : '追番',
            color: _favorite ? const Color(0xFFFFB020) : muted,
            onTap: _savingFavorite ? null : _toggleFavorite,
          ),
          _actionItem(
            icon: BIcons.download,
            label: '下载',
            color: muted,
            onTap: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('暂不支持缓存下载，请在线观看')));
            },
          ),
          _actionItem(
            icon: BIcons.share,
            label: '分享',
            color: muted,
            onTap: _sharePlayback,
          ),
        ],
      ),
    );
  }

  Widget _actionItem({
    required BrandIconData icon,
    required String label,
    Color? color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BrandIcon(icon, color: color, size: 22),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _episodeHeading(bool isDark, PlayGroup? currentGroup) {
    final count = currentGroup?.episodes.length ?? 0;
    final trailing = widget.video.remarks.isNotEmpty
        ? widget.video.remarks
        : (count > 0 ? '全$count话' : '');
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Row(
      children: [
        Text(
          '选集',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
          ),
        ),
        BrandIcon(BIcons.chevronRight, size: 18, color: muted),
        const Spacer(),
        if (trailing.isNotEmpty)
          Text(trailing, style: TextStyle(fontSize: 12, color: muted)),
      ],
    );
  }

  Widget _episodeCards() {
    return EpisodeCardList(
      playGroups: widget.video.playGroups,
      currentGroupIndex: _currentGroupIndex,
      currentEpisodeIndex: _currentEpisodeIndex,
      posterUrl: widget.video.picture,
      onSelected: _switchEpisode,
    );
  }

  Widget _relatedHeading(bool isDark) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Row(
      children: [
        Text(
          '猜你喜欢',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
          ),
        ),
        BrandIcon(BIcons.chevronRight, size: 18, color: muted),
      ],
    );
  }

  Widget _danmakuSheet(bool isDark) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final mineId = _appState.user?['id']?.toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            Text(
              _appState.danmakuEnabled ? '弹幕开着' : '弹幕关着',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text('${_danmaku.length} 条', style: TextStyle(color: muted)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '弹幕会按这一集的播放时间出现在画面上。想慢慢聊，去评论区。',
          style: TextStyle(fontSize: 13, height: 1.5, color: muted),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: _sendingDanmaku ? null : _composeDanmaku,
            child: const Text('发弹幕'),
          ),
        ),
        const SizedBox(height: 12),
        if (_danmaku.isEmpty)
          Text('这一集还没有弹幕。', style: TextStyle(color: muted))
        else
          for (final item in _danmaku)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                item.content,
                style: TextStyle(color: ink, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_clock(item.playTimeMs)}  ${item.authorName}',
                style: TextStyle(color: muted),
              ),
              trailing: mineId == '${item.userId}'
                  ? IconButton(
                      tooltip: '删除',
                      onPressed: () => _removeDanmaku(item),
                      icon: const BrandIcon(BIcons.trash),
                    )
                  : null,
            ),
      ],
    );
  }

  String _clock(int milliseconds) {
    final total = milliseconds < 0 ? 0 : milliseconds ~/ 1000;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _commentSheet() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        VideoCommentSection(
          targetId: widget.video.id,
          onTotal: (total) {
            if (_commentTotal == total) return;
            setState(() => _commentTotal = total);
          },
        ),
      ],
    );
  }

  Future<void> _toggleFavorite() async {
    setState(() => _savingFavorite = true);
    try {
      await _appState.toggleFavorite(widget.video);
      if (!mounted) return;
      setState(() => _favorite = _appState.isFavorite(widget.video.id));
      if (_appState.accountError != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_appState.accountError!)));
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  Future<void> _sharePlayback() async {
    final group =
        widget.video.playGroups.isNotEmpty &&
            _currentGroupIndex < widget.video.playGroups.length
        ? widget.video.playGroups[_currentGroupIndex]
        : null;
    final episode =
        group != null && _currentEpisodeIndex < group.episodes.length
        ? group.episodes[_currentEpisodeIndex].name
        : '';
    final text = [
      widget.video.name,
      episode,
    ].where((item) => item.isNotEmpty).join(' · ');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制片名，可以分享给同好')));
  }

  Future<void> _openRelated(VideoRecord video) async {
    final wasPlaying = _isPlaying;
    await _player.pause();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailScreen(videoId: video.id)),
    );
    if (mounted && wasPlaying) _player.play();
  }

  Widget _buildDesktopMetaCard(bool isDark) {
    if (widget.video.content.isEmpty && widget.video.tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.video.typeName,
                  style: const TextStyle(
                    color: AppColors.primary500,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  [
                    widget.video.area,
                    widget.video.year,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (widget.video.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.video.tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkBg : AppColors.lightBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#$tag',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (widget.video.content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                widget.video.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopShortcutGuide(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkCard.withValues(alpha: 0.5)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const BrandIcon(
              BIcons.keyboard,
              size: 16,
              color: AppColors.primary500,
            ),
            const SizedBox(width: 8),
            const Text(
              '桌面快捷键:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '空格 播放/暂停  ·  ←/→ 快退进5s  ·  ↑/↓ 调音量  ·  [/] 上下集  ·  F 全屏',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 画面渲染与多模式自适应
  Widget _buildVideoSurface() {
    BoxFit fit;
    double? customAspect;

    switch (_aspectMode) {
      case AspectRatioMode.contain:
        fit = BoxFit.contain;
        break;
      case AspectRatioMode.widescreen:
        fit = BoxFit.fill;
        customAspect = 16 / 9;
        break;
      case AspectRatioMode.classic:
        fit = BoxFit.fill;
        customAspect = 4 / 3;
        break;
      case AspectRatioMode.fill:
        fit = BoxFit.cover;
        break;
    }

    Widget videoWidget = Center(
      child: customAspect != null
          ? AspectRatio(
              aspectRatio: customAspect,
              child: Video(
                controller: _videoController,
                fit: fit,
                controls: NoVideoControls,
              ),
            )
          : Video(
              controller: _videoController,
              fit: fit,
              controls: NoVideoControls,
            ),
    );

    if (_isEnhanced) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(_auroraMatrix),
        child: videoWidget,
      );
    }
    return videoWidget;
  }

  String _aspectModeLabel(AspectRatioMode mode) {
    switch (mode) {
      case AspectRatioMode.contain:
        return '自适应';
      case AspectRatioMode.widescreen:
        return '16:9';
      case AspectRatioMode.classic:
        return '4:3';
      case AspectRatioMode.fill:
        return '铺满';
    }
  }

  // 现代质感品牌控制层
  Widget _buildControlsOverlay(
    Episode? currentEp,
    PlayGroup? currentGroup,
    List<PlayGroup> groups,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxWidth < 560 || constraints.maxHeight < 280;
        final bufferRatio = _duration.inMilliseconds > 0
            ? (_buffer.inMilliseconds / _duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. 顶部环境微光渐变 (暗夜星空质感)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: isCompact ? 90 : 130,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF070B16).withValues(alpha: 0.88),
                        const Color(0xFF070B16).withValues(alpha: 0.40),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 2. 底部环境微光渐变
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: isCompact ? 110 : 150,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF070B16).withValues(alpha: 0.45),
                        const Color(0xFF070B16).withValues(alpha: 0.95),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 3. 屏幕锁定状态按键 (防误触设计)
            BrandPlayerScreenLock(
              isLocked: _isLocked,
              isCompact: isCompact,
              onToggleLock: () {
                setState(() {
                  _isLocked = !_isLocked;
                  if (_isLocked) _showFullscreenDrawer = false;
                });
                _showHudMessage(
                  _isLocked ? '屏幕已锁定 (防误触)' : '屏幕已解锁',
                  _isLocked ? BIcons.lock : BIcons.unlock,
                );
                _resetHideControlsTimer();
              },
            ),

            // 4. 未锁定时渲染完整控制框架
            if (!_isLocked) ...[
              // 顶部控制栏（桌面非全屏时为右上角原生窗口按钮让位）
              // 悬停期间控制层保持可见，标题栏随时可拖拽
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: MouseRegion(
                  onEnter: (_) => _enterControlsHover(),
                  onExit: (_) => _exitControlsHover(),
                  child: BrandPlayerTopBar(
                    title: widget.video.name,
                    episodeName: currentEp?.name,
                    serverName: currentGroup?.server,
                    isEnhanced: _isEnhanced,
                    aspectModeLabel: _aspectModeLabel(_aspectMode),
                    isCompact: isCompact,
                    topInset: _nativeWindowControlsInset(),
                    draggable: !_isFullscreen,
                    // 桌面非全屏：工具胶囊收进更多菜单，右上角放投屏/分享
                    showTools: _isFullscreen,
                    trailing: (!_isFullscreen && Responsive.isDesktop(context))
                        ? [
                            _topIconButton(
                              icon: BIcons.ratio,
                              tooltip: '投屏到电视',
                              onTap: () => _showTopToast('投屏功能即将上线'),
                            ),
                            _topIconButton(
                              icon: BIcons.share,
                              tooltip: '分享',
                              onTap: _showShareDialog,
                            ),
                            const SizedBox(width: 6),
                          ]
                        : null,
                    onBack: () {
                      if (_isFullscreen) {
                        _toggleFullscreen();
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                    onToggleEnhance: _toggleEnhance,
                    onToggleAspect: _toggleAspectMode,
                  ),
                ),
              ),

              // 居中主控岛屿
              Center(
                child: BrandPlayerCenterDeck(
                  isPlaying: _isPlaying,
                  isCompact: isCompact,
                  onTogglePlay: _togglePlayPause,
                  onPlayPrev: _currentEpisodeIndex > 0
                      ? _playPrevEpisode
                      : null,
                  onPlayNext:
                      (currentGroup != null &&
                          _currentEpisodeIndex + 1 <
                              currentGroup.episodes.length)
                      ? _playNextEpisode
                      : null,
                  onSeekBackward: () => _seekBy(-10),
                  onSeekForward: () => _seekBy(10),
                ),
              ),

              // 底部磨砂玻璃悬浮底栏（悬停期间保持可见）
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: MouseRegion(
                  onEnter: (_) => _enterControlsHover(),
                  onExit: (_) => _exitControlsHover(),
                  child: BrandPlayerBottomDock(
                    position: _position,
                    duration: _duration,
                    bufferProgress: bufferRatio,
                    isPlaying: _isPlaying,
                    isFullscreen: _isFullscreen,
                    danmakuEnabled: _appState.danmakuEnabled,
                    speed: _currentSpeed,
                    volume: _volume,
                    isCompact: isCompact,
                    formatDuration: _formatDuration,
                    onSeek: (val) {
                      if (_watchGuestLocked()) return;
                      _seekWithSync(Duration(milliseconds: val.toInt()));
                      _resetHideControlsTimer();
                    },
                    onTogglePlay: _togglePlayPause,
                    onPlayPrev: _playPrevEpisode,
                    onPlayNext:
                        (currentGroup != null &&
                            _currentEpisodeIndex + 1 <
                                currentGroup.episodes.length)
                        ? _playNextEpisode
                        : null,
                    onVolume: _setDockVolume,
                    onToggleDanmaku: _toggleDanmaku,
                    onSelectSpeed: () {
                      setState(() {
                        _showSpeedPanel = !_showSpeedPanel;
                        if (_showSpeedPanel) {
                          _showFullscreenDrawer = false;
                        }
                      });
                      _resetHideControlsTimer();
                    },
                    onToggleDrawer: _isFullscreen
                        ? () {
                            setState(() {
                              _showFullscreenDrawer = !_showFullscreenDrawer;
                              if (_showFullscreenDrawer) {
                                _drawerRange =
                                    _currentEpisodeIndex ~/ episodeRangeSize;
                              }
                            });
                            _resetHideControlsTimer();
                          }
                        : (!Responsive.isDesktop(context)
                              ? () {
                                  setState(() {
                                    _sheetIndex = 0;
                                  });
                                }
                              : null),
                    onToggleFullscreen: _toggleFullscreen,
                    moreItems: _moreMenuItems(groups),
                    onMoreSelected: _onMoreSelected,
                    bubbleLabelFor: _bubbleLabelFor,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 播放器顶栏右侧的圆形磨砂小按钮（投屏/分享）
  Widget _topIconButton({
    required BrandIconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return BrandPlayerButton(
      icon: icon,
      onPressed: onTap,
      size: 38,
      iconSize: 18,
      tooltip: tooltip,
    );
  }

  // 全屏内嵌选集抽屉 (亚克力磨砂质感与流光卡片)
  Widget _buildFullscreenDrawer(List<PlayGroup> groups) {
    final currentGroup = groups.isNotEmpty && _currentGroupIndex < groups.length
        ? groups[_currentGroupIndex]
        : null;
    final episodes = currentGroup?.episodes ?? [];

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 300,
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: const Color(0xFF0F172A).withValues(alpha: 0.90),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 16,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '选集与线路',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    BrandPlayerButton(
                      icon: BIcons.close,
                      size: 32,
                      iconSize: 18,
                      onPressed: () {
                        setState(() {
                          _showFullscreenDrawer = false;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 线路切换
                DesktopHorizontalScroll(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(groups.length, (index) {
                        final isSel = _currentGroupIndex == index;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: BrandPill(
                            label: Text(groups[index].server),
                            selected: isSel,
                            onSelected: (selected) {
                              if (selected) {
                                _switchEpisode(index, _currentEpisodeIndex);
                              }
                            },
                            onDark: true,
                          ),
                        );
                      }),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                if (episodeRanges(episodes.length).length > 1) ...[
                  DesktopHorizontalScroll(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (index, range) in episodeRanges(
                            episodes.length,
                          ).indexed)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: BrandPill(
                                label: Text(range.label),
                                selected: _drawerRange == index,
                                onDark: true,
                                onSelected: (selected) {
                                  if (!selected) return;
                                  setState(() => _drawerRange = index);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 集数网格。超过 99 集时只显示当前分页。
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final ranges = episodeRanges(episodes.length);
                      final range = ranges.isEmpty
                          ? const EpisodeRange(0, 0)
                          : ranges[_drawerRange.clamp(0, ranges.length - 1)];
                      final visible = episodes.isEmpty
                          ? 0
                          : range.end - range.start;
                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 2.0,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                            ),
                        itemCount: visible,
                        itemBuilder: (context, idx) {
                          final episodeIndex = range.start + idx;
                          final isPlaying =
                              episodeIndex == _currentEpisodeIndex;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _switchEpisode(
                              _currentGroupIndex,
                              episodeIndex,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                gradient: isPlaying
                                    ? AppColors.brandGradient
                                    : null,
                                color: isPlaying
                                    ? null
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isPlaying
                                      ? Colors.transparent
                                      : Colors.white.withValues(alpha: 0.12),
                                  width: 0.8,
                                ),
                                boxShadow: isPlaying
                                    ? [
                                        BoxShadow(
                                          color: AppColors.purple.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                episodes[episodeIndex].name,
                                style: TextStyle(
                                  color: isPlaying
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: isPlaying
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
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
