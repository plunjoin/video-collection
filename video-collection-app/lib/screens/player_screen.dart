import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../widgets/brand_controls.dart';
import '../widgets/brand_player_controls.dart';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../models/watch_together_model.dart';
import '../services/analytics_tracker.dart';
import '../services/fullscreen_service.dart';
import '../services/api_service.dart';
import '../services/client_playlist_service.dart';
import '../services/watch_together_service.dart';
import '../widgets/anime_poster_card.dart';
import '../widgets/desktop_horizontal_scroll.dart';
import '../widgets/brand_intro.dart';
import '../widgets/watch_together_widgets.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/danmaku_overlay.dart';
import '../widgets/episode_selector.dart';
import '../widgets/video_comments.dart';
import '../mixins/watch_together_mixin.dart';
import 'account_screen.dart';
import 'anime_detail_screen.dart';

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

  const PlayerScreen({
    super.key,
    required this.video,
    this.initialGroupIndex = 0,
    this.initialEpisodeIndex = 0,
    this.initialPosition = Duration.zero,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WatchTogetherMixin {
  late int _currentGroupIndex;
  late int _currentEpisodeIndex;
  late final AppStateProvider _appState;
  Duration? _resumePosition;
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
  Timer? _hideControlsTimer;
  bool _isFullscreen = false;
  bool _isLocked = false;
  bool _changingFullscreen = false;
  final _fullscreen = FullscreenService();
  Timer? _historyTimer;
  bool _isAutoPlayingNext = false;
  int _nextCountdownSeconds = 3;
  Timer? _nextCountdownTimer;

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
  IconData? _hudIcon;
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

  // 播放页下半屏：视频 / 弹幕 / 评论。选集只使用剧集卡片。
  int _sheetIndex = 0;
  List<DanmakuItem> _danmaku = [];
  int _danmakuGeneration = 0;
  bool _sendingDanmaku = false;
  bool _savingFavorite = false;
  bool _favorite = false;
  int _commentTotal = 0;
  List<VideoRecord> _related = [];

  // WatchTogetherMixin 需要的 getter 实现
  @override
  Player get player => _player;
  
  @override
  Duration get position => _position;
  
  @override
  bool get isPlaying => _isPlaying;
  
  @override
  double get currentSpeed => _currentSpeed;
  
  @override
  int get currentGroupIndex => _currentGroupIndex;
  
  @override
  int get currentEpisodeIndex => _currentEpisodeIndex;
  
  // WatchTogetherMixin 需要的方法实现
  @override
  void onSwitchEpisode(int groupIndex, int episodeIndex) {
    _switchEpisode(groupIndex, episodeIndex);
  }
  
  @override
  void onShowMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

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
    AnalyticsTracker().event('play', page: 'app://play', targetId: widget.video.id);

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
    _loadAndPlayCurrentEpisode();
    unawaited(_loadRelated());
    unawaited(_loadDanmaku());
    
    // 初始化 Watch Together
    initWatchTogether();
    _initWatchTogetherUser();
  }
  
  // 初始化 Watch Together 用户ID
  Future<void> _initWatchTogetherUser() async {
    if (_appState.isLoggedIn && _appState.user != null) {
      final userId = _appState.user!['id'] as int?;
      if (userId != null) {
        WatchTogetherService().setCurrentUserId(userId);
      }
    }
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
    // 清理 Watch Together
    disposeWatchTogether();
    
    ++_sourceGeneration;
    unawaited(_pendingPlaylist?.dispose());
    if (!_hasError && _duration > Duration.zero) {
      _recordHistory(countHit: false);
    }
    _historyTimer?.cancel();
    _hideControlsTimer?.cancel();
    _hideHudTimer?.cancel();
    _quickSeekTipTimer?.cancel();
    _nextCountdownTimer?.cancel();

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
          if (resume > Duration.zero && resume < dur) _player.seek(resume);
        }
      }),
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        setState(() {
          _isPlaying = playing;
        });
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
    // 一起看期间不记录播放历史
    if (!shouldRecordHistory()) return;
    
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
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _showControls = false;
            _showFullscreenDrawer = false;
          });
        }
      });
    }
  }

  void _showHudMessage(String text, IconData icon) {
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
    // 如果在一起看中且不是房主,阻止操作
    if (shouldBlockLocalControl()) {
      onShowMessage('只有房主可以控制播放');
      return;
    }
    
    // 如果是房主,通过Watch Together发送意图
    if (isInWatchTogether && isWatchTogetherHost) {
      if (_isPlaying) {
        watchTogetherPause();
      } else {
        watchTogetherPlay();
      }
    }
    
    if (_isPlaying) _recordHistory(countHit: false);
    _player.playOrPause();
    _resetHideControlsTimer();
  }

  void _seekBy(int seconds) {
    // 如果在一起看中且不是房主,阻止操作
    if (shouldBlockLocalControl()) {
      onShowMessage('只有房主可以快进快退');
      return;
    }
    
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    
    // 如果是房主,通过Watch Together发送意图
    if (isInWatchTogether && isWatchTogetherHost) {
      watchTogetherSeek(target);
    }
    
    _player.seek(target);

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

  void _switchEpisode(int groupIndex, int episodeIndex) {
    // 如果在一起看中且不是房主,阻止操作
    if (shouldBlockLocalControl()) {
      onShowMessage('只有房主可以切换剧集');
      return;
    }
    
    // 如果是房主,通过Watch Together发送意图
    if (isInWatchTogether && isWatchTogetherHost) {
      watchTogetherSwitchEpisode(groupIndex, episodeIndex);
    }
    
    if (!_hasError && _duration > Duration.zero) {
      _recordHistory(countHit: false);
    }
    _resumePosition = null;
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

  void _setSpeed(double speed) {
    // 如果在一起看中且不是房主,阻止操作
    if (shouldBlockLocalControl()) {
      onShowMessage('只有房主可以调整播放速率');
      return;
    }
    
    // 如果是房主,通过Watch Together发送意图
    if (isInWatchTogether && isWatchTogetherHost) {
      watchTogetherSetRate(speed);
    }
    
    setState(() {
      _currentSpeed = speed;
    });
    _player.setRate(speed);
    unawaited(_appState.setPlaybackSpeed(speed));
    final speedStr = speed == speed.roundToDouble()
        ? '${speed.toInt()}.0'
        : ((speed * 10) % 1 == 0
            ? speed.toStringAsFixed(1)
            : speed.toStringAsFixed(2));
    _showHudMessage('${speedStr}x 倍速', Icons.speed_rounded);
  }

  void _startLongPressSpeedUp() {
    if (_isLocked || !_isPlaying || _hasError || _isDraggingProgress) return;
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
          _showHudMessage('画面比例: 16:9 宽屏', Icons.aspect_ratio_rounded);
          break;
        case AspectRatioMode.widescreen:
          _aspectMode = AspectRatioMode.classic;
          _showHudMessage('画面比例: 4:3 经典', Icons.aspect_ratio_rounded);
          break;
        case AspectRatioMode.classic:
          _aspectMode = AspectRatioMode.fill;
          _showHudMessage('画面比例: 铺满全屏', Icons.fullscreen_rounded);
          break;
        case AspectRatioMode.fill:
          _aspectMode = AspectRatioMode.contain;
          _showHudMessage('画面比例: 居中自适应', Icons.fit_screen_rounded);
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
      Icons.auto_awesome_rounded,
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
        _showHudMessage('音量: ${newVol.toInt()}%', Icons.volume_up_rounded);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        final newVol = (_volume - 10).clamp(0.0, 100.0);
        setState(() => _volume = newVol);
        _player.setVolume(newVol);
        _showHudMessage(
          '音量: ${newVol.toInt()}%',
          newVol == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
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
          newVol == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
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
      next ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
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
              final width = MediaQuery.of(context).size.width;
              if (details.localPosition.dx < width / 2) {
                _seekBy(-5);
              } else {
                _seekBy(5);
              }
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
                  newVol == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                );
              } else {
                // 左半屏调亮度
                final newBri = (_brightness + delta / 100.0).clamp(0.2, 1.0);
                setState(() => _brightness = newBri);
                _showHudMessage(
                  '亮度: ${(newBri * 100).toInt()}%',
                  Icons.brightness_6_rounded,
                );
              }
            },
            onHorizontalDragStart: (details) {
              if (_isLocked || _isLongPressSpeeding) return;
              // 如果在一起看中且不是房主,阻止拖拽
              if (shouldBlockLocalControl()) {
                onShowMessage('只有房主可以拖动进度');
                return;
              }
              _isDraggingProgress = true;
              _dragTargetSeconds = _position.inSeconds.toDouble();
            },
            onHorizontalDragUpdate: (details) {
              if (_isLocked || _isLongPressSpeeding || !_isDraggingProgress) return;
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
                Icons.fast_forward_rounded,
              );
            },
            onHorizontalDragEnd: (details) {
              if (_isLocked) return;
              if (_isDraggingProgress) {
                _isDraggingProgress = false;
                final targetPosition = Duration(seconds: _dragTargetSeconds.toInt());
                
                // 如果是房主,通过Watch Together发送意图
                if (isInWatchTogether && isWatchTogetherHost) {
                  watchTogetherSeek(targetPosition);
                }
                
                _player.seek(targetPosition);
                _resetHideControlsTimer();
              }
            },
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
                          milliseconds: (_dragTargetSeconds * 1000).round(),
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
                  color: Colors.black.withValues(alpha: 1.0 - _brightness),
                ),

              // 双击快进快退反馈浮层
              if (_showQuickSeekTip)
                BrandPlayerHUD(
                  icon: _quickSeekTip.startsWith('+')
                      ? Icons.fast_forward_rounded
                      : Icons.fast_rewind_rounded,
                  text: _quickSeekTip,
                ),

              // HUD 浮层 (音量/亮度/滑动定位)
              if (_showHud && !_showQuickSeekTip)
                BrandPlayerHUD(
                  icon: _hudIcon,
                  text: _hudText,
                ),

              if (_isBuffering && !_hasError)
                const Center(child: BrandIntro(width: 300, onDark: true)),

              // 错误浮层
              if (_hasError)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.rose.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
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
                              onPressed: () => _loadAndPlayCurrentEpisode(),
                              icon: const Icon(
                                Icons.refresh_rounded,
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
                        color: AppColors.primary500.withValues(alpha: 0.5),
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
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.14),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.35),
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
                  alignment:
                      isCompact ? Alignment.center : Alignment.bottomRight,
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
            ],
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
      return Scaffold(
        body: Column(
          children: [
            // 桌面端无边框沉浸式窗口标题栏 (包含返回、拖拽移动、画质增强开关与窗口控制)
            DesktopWindowTitleBar(
              isDark: isDark,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.video.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary600.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '桌面剧场模式',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _isEnhanced
                          ? Icons.auto_awesome_rounded
                          : Icons.auto_awesome_outlined,
                      color: _isEnhanced ? AppColors.gold : null,
                      size: 16,
                    ),
                    tooltip: '极光画质增强',
                    onPressed: _toggleEnhance,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧：大屏播放器 + 视频 / 弹幕 / 评论
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(aspectRatio: 16 / 9, child: playerCore),
                        _sheetTabs(isDark),
                        Expanded(
                          child: IndexedStack(
                            index: _sheetIndex,
                            sizing: StackFit.expand,
                            children: [
                              _videoSheet(
                                isDark,
                                currentEp,
                                currentGroup,
                                embedEpisodes: false,
                              ),
                              _danmakuSheet(isDark),
                              _commentSheet(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 右侧：常驻专属选集面板
                  Container(
                    width: 360,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      border: Border(
                        left: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: _episodeHeading(isDark, currentGroup),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: _episodeCards(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 移动端：播放器贴顶，下面是视频 / 弹幕 / 评论。
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF7F8FB),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: playerCore),
            _sheetTabs(isDark),
            Expanded(
              child: IndexedStack(
                index: _sheetIndex,
                sizing: StackFit.expand,
                children: [
                  _videoSheet(isDark, currentEp, currentGroup),
                  _danmakuSheet(isDark),
                  _commentSheet(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetTabs(bool isDark) {
    final labels = [
      '视频',
      '弹幕',
      _commentTotal > 0 ? '评论 ${formatAudienceCount(_commentTotal)}' : '评论',
    ];
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Material(
      color: isDark ? AppColors.darkBg : Colors.white,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _sheetIndex = index),
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Column(
                    children: [
                      Text(
                        labels[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: _sheetIndex == index
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: _sheetIndex == index ? ink : muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 3,
                        width: 18,
                        decoration: BoxDecoration(
                          color: _sheetIndex == index
                              ? AppColors.primary600
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
      ),
    );
  }

  Widget _videoSheet(
    bool isDark,
    Episode? currentEp,
    PlayGroup? currentGroup, {
    bool embedEpisodes = true,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _danmakuBar(isDark),
        const SizedBox(height: 14),
        _titleBlock(isDark, currentEp, currentGroup),
        const SizedBox(height: 16),
        _actionRow(isDark),
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
                    const Icon(
                      Icons.local_fire_department_rounded,
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
                    const Icon(
                      Icons.play_circle_fill_rounded,
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
            icon: Icons.thumb_up_alt_outlined,
            label: widget.video.hits > 0
                ? formatAudienceCount(widget.video.hits)
                : '点赞',
            color: muted,
          ),
          _actionItem(
            icon: _favorite ? Icons.star_rounded : Icons.star_border_rounded,
            label: _favorite ? '已追番' : '追番',
            color: _favorite ? const Color(0xFFFFB020) : muted,
            onTap: _savingFavorite ? null : _toggleFavorite,
          ),
          _actionItem(
            icon: Icons.download_rounded,
            label: '下载',
            color: muted,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('暂不支持缓存下载，请在线观看')),
              );
            },
          ),
          _actionItem(
            icon: Icons.share_outlined,
            label: '分享',
            color: muted,
            onTap: _sharePlayback,
          ),
        ],
      ),
    );
  }

  Widget _actionItem({
    required IconData icon,
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
            Icon(icon, color: color, size: 22),
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
        Icon(Icons.chevron_right_rounded, size: 18, color: muted),
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
        Icon(Icons.chevron_right_rounded, size: 18, color: muted),
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
                      icon: const Icon(Icons.delete_outline_rounded),
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
            const Icon(
              Icons.keyboard_rounded,
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
            ? (_buffer.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
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
                  _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                );
                _resetHideControlsTimer();
              },
            ),

            // 4. 未锁定时渲染完整控制框架
            if (!_isLocked) ...[
              // 顶部控制栏
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: BrandPlayerTopBar(
                  title: widget.video.name,
                  episodeName: currentEp?.name,
                  serverName: currentGroup?.server,
                  isEnhanced: _isEnhanced,
                  aspectModeLabel: _aspectModeLabel(_aspectMode),
                  isCompact: isCompact,
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
              
              // 一起看房间信息卡片 (如果已在房间中)
              if (isInWatchTogether && watchRoomInfo != null)
                Positioned(
                  top: isCompact ? 50 : 70,
                  left: 12,
                  right: 12,
                  child: WatchRoomInfoWidget(
                    roomInfo: watchRoomInfo!,
                    isHost: isWatchTogetherHost,
                    onLeave: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('离开房间'),
                          content: const Text('确定要离开一起看房间吗?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('离开'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        if (watchRoomInfo != null) {
                          await WatchTogetherService().leaveRoom(watchRoomInfo!.room.id);
                        }
                        await WatchTogetherService().disconnectWebSocket();
                        setState(() {});
                      }
                    },
                  ),
                ),
              
              // 一起看按钮 (如果未在房间中且已登录)
              if (!isInWatchTogether && _appState.isLoggedIn)
                Positioned(
                  top: isCompact ? 50 : 70,
                  right: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 创建房间按钮
                      Material(
                        color: Colors.purple.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            try {
                              final room = await WatchTogetherService().createRoom(
                                videoId: widget.video.id,
                                routeIndex: _currentGroupIndex,
                                episodeIndex: _currentEpisodeIndex,
                              );
                              
                              // 加入自己创建的房间
                              await WatchTogetherService().joinRoom(room.id);
                              await WatchTogetherService().connectWebSocket(room.id);
                              
                              if (mounted) {
                                setState(() {});
                                // 显示房间码
                                showDialog(
                                  context: context,
                                  builder: (context) => RoomCreatedDialog(room: room),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                onShowMessage('创建房间失败: $e');
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.people_outline,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '创建一起看',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 加入房间按钮
                      Material(
                        color: Colors.blue.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final roomInfo = await showDialog<RoomInfo>(
                              context: context,
                              builder: (context) => const JoinWatchRoomDialog(),
                            );
                            if (roomInfo != null && mounted) {
                              try {
                                await WatchTogetherService().joinRoom(roomInfo.room.id);
                                await WatchTogetherService().connectWebSocket(roomInfo.room.id);
                                
                                // 切换到房间的视频和剧集
                                if (roomInfo.room.videoId != widget.video.id) {
                                  onShowMessage('房间视频与当前视频不同,请返回重新进入');
                                } else if (roomInfo.state.routeIndex != _currentGroupIndex ||
                                           roomInfo.state.episodeIndex != _currentEpisodeIndex) {
                                  _switchEpisode(
                                    roomInfo.state.routeIndex,
                                    roomInfo.state.episodeIndex,
                                  );
                                }
                                
                                setState(() {});
                              } catch (e) {
                                if (mounted) {
                                  onShowMessage('加入房间失败: $e');
                                }
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.group_add,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '加入房间',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 居中主控岛屿
              Center(
                child: BrandPlayerCenterDeck(
                  isPlaying: _isPlaying,
                  isCompact: isCompact,
                  onTogglePlay: _togglePlayPause,
                  onPlayPrev:
                      _currentEpisodeIndex > 0 ? _playPrevEpisode : null,
                  onPlayNext: (currentGroup != null &&
                          _currentEpisodeIndex + 1 < currentGroup.episodes.length)
                      ? _playNextEpisode
                      : null,
                  onSeekBackward: () => _seekBy(-10),
                  onSeekForward: () => _seekBy(10),
                ),
              ),

              // 底部磨砂玻璃悬浮底栏
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: BrandPlayerBottomDock(
                  position: _position,
                  duration: _duration,
                  bufferProgress: bufferRatio,
                  isPlaying: _isPlaying,
                  isFullscreen: _isFullscreen,
                  danmakuEnabled: _appState.danmakuEnabled,
                  speed: _currentSpeed,
                  isCompact: isCompact,
                  formatDuration: _formatDuration,
                  onSeek: (val) {
                    // 如果在一起看中且不是房主,阻止操作
                    if (shouldBlockLocalControl()) {
                      onShowMessage('只有房主可以拖动进度');
                      return;
                    }
                    
                    final targetPosition = Duration(milliseconds: val.toInt());
                    
                    // 如果是房主,通过Watch Together发送意图
                    if (isInWatchTogether && isWatchTogetherHost) {
                      watchTogetherSeek(targetPosition);
                    }
                    
                    _player.seek(targetPosition);
                    _resetHideControlsTimer();
                  },
                  onTogglePlay: _togglePlayPause,
                  onPlayNext: (currentGroup != null &&
                          _currentEpisodeIndex + 1 < currentGroup.episodes.length)
                      ? _playNextEpisode
                      : null,
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
                ),
              ),
            ],
          ],
        );
      },
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
                      icon: Icons.close_rounded,
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
                          final isPlaying = episodeIndex == _currentEpisodeIndex;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () =>
                                _switchEpisode(_currentGroupIndex, episodeIndex),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                gradient:
                                    isPlaying ? AppColors.brandGradient : null,
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
