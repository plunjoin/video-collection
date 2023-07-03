import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/brand_controls.dart';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../services/fullscreen_service.dart';
import '../widgets/brand_intro.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/episode_selector.dart';

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

class _PlayerScreenState extends State<PlayerScreen> {
  late int _currentGroupIndex;
  late int _currentEpisodeIndex;
  late final AppStateProvider _appState;
  Duration? _resumePosition;

  // MediaKit 流媒体底层播放器
  late final Player _player;
  late final VideoController _videoController;

  // 播放器状态流监听
  final List<StreamSubscription> _subscriptions = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasError = false;
  String _errorMessage = '';

  // 交互控制
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isFullscreen = false;
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
  final List<double> _speedList = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

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
    _resumePosition = widget.initialPosition;
    _currentGroupIndex = widget.initialGroupIndex;
    _currentEpisodeIndex = widget.initialEpisodeIndex;

    // 实例化媒体播放引擎
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024, // 32MB 极速缓冲
      ),
    );
    _videoController = VideoController(_player);

    _historyTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isPlaying && !_hasError) _recordHistory(countHit: false);
    });
    _listenPlayerStreams();
    _loadAndPlayCurrentEpisode();
  }

  @override
  void dispose() {
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
    _player.dispose();

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

    try {
      final cleanUrl = currentEp.url.trim();
      await _player.open(Media(cleanUrl), play: true);
      await _player.setRate(_currentSpeed);
      await _player.setVolume(_volume);

      _recordHistory();
      _resetHideControlsTimer();
    } catch (e) {
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
    if (_isPlaying) _recordHistory(countHit: false);
    _player.playOrPause();
    _resetHideControlsTimer();
  }

  void _seekBy(int seconds) {
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
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
    });
    _loadAndPlayCurrentEpisode();
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
    setState(() {
      _currentSpeed = speed;
    });
    _player.setRate(speed);
    _showHudMessage('${speed}x 倍速', Icons.speed_rounded);
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
      }
    }
    return KeyEventResult.ignored;
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _showControls = !_showControls;
            if (!_showControls) _showFullscreenDrawer = false;
          });
          _resetHideControlsTimer();
        },
        onDoubleTapDown: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.localPosition.dx < width / 2) {
            _seekBy(-5);
          } else {
            _seekBy(5);
          }
        },
        onVerticalDragUpdate: (details) {
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
          _isDraggingProgress = true;
          _dragTargetSeconds = _position.inSeconds.toDouble();
        },
        onHorizontalDragUpdate: (details) {
          if (!_isDraggingProgress) return;
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
          if (_isDraggingProgress) {
            _isDraggingProgress = false;
            _player.seek(Duration(seconds: _dragTargetSeconds.toInt()));
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

              // 软调亮度遮罩
              if (_brightness < 1.0)
                Container(
                  color: Colors.black.withValues(alpha: 1.0 - _brightness),
                ),

              // 双击快进快退反馈浮层
              if (_showQuickSeekTip)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.primary500.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _quickSeekTip.startsWith('+')
                              ? Icons.fast_forward_rounded
                              : Icons.fast_rewind_rounded,
                          color: AppColors.primary400,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _quickSeekTip,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // HUD 浮层 (音量/亮度/滑动定位)
              if (_showHud && !_showQuickSeekTip)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hudIcon != null) ...[
                          Icon(_hudIcon, color: AppColors.primary400, size: 24),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          _hudText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('重试播放'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary600,
                              ),
                            ),
                            if (groups.length > 1) ...[
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () {
                                  final nextGroup =
                                      (_currentGroupIndex + 1) % groups.length;
                                  _switchEpisode(
                                    nextGroup,
                                    _currentEpisodeIndex,
                                  );
                                },
                                icon: const Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 16,
                                ),
                                label: const Text('切换线路'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white38),
                                ),
                              ),
                            ],
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
                                side: const BorderSide(color: Colors.white38),
                              ),
                              child: const Text(
                                '取消连播',
                                style: TextStyle(color: Colors.white),
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
                              ),
                              child: const Text('立即切集'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // 控制蒙层 (顶部 + 底部)
              if (_showControls) _buildControlsOverlay(currentEp, currentGroup),

              // 全屏模式下的内嵌选集抽屉
              if (_isFullscreen && _showFullscreenDrawer)
                _buildFullscreenDrawer(groups),
            ],
          ),
        ),
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
                  // 左侧：大屏播放器 + 信息详情 + 快捷键指南
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(aspectRatio: 16 / 9, child: playerCore),
                          _buildPlayerInfoBar(currentEp, currentGroup, isDark),
                          _buildDesktopMetaCard(isDark),
                          _buildDesktopShortcutGuide(isDark),
                        ],
                      ),
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.playlist_play_rounded,
                                    color: AppColors.primary500,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '选集播放 (${currentGroup?.episodes.length ?? 0}话)',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.lightTextPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.emerald.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '自动连播中',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.emerald,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: EpisodeSelectorWidget(
                              playGroups: groups,
                              currentGroupIndex: _currentGroupIndex,
                              currentEpisodeIndex: _currentEpisodeIndex,
                              onSelected: (groupIndex, epIndex) {
                                _switchEpisode(groupIndex, epIndex);
                              },
                            ),
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

    // 移动端：上下流式布局
    return Scaffold(
      appBar: BrandAppBar(
        title: Text(widget.video.name),
        actions: [
          IconButton(
            icon: Icon(
              _isEnhanced
                  ? Icons.auto_awesome_rounded
                  : Icons.auto_awesome_outlined,
              color: _isEnhanced ? AppColors.gold : null,
            ),
            tooltip: '极光画质增强',
            onPressed: _toggleEnhance,
          ),
        ],
      ),
      body: Column(
        children: [
          // 播放器窗口 (16:9)
          AspectRatio(aspectRatio: 16 / 9, child: playerCore),

          // 核心控制与信息条
          _buildPlayerInfoBar(currentEp, currentGroup, isDark),

          Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),

          // 选集列表与线路切换
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '选集列表 (${currentGroup?.episodes.length ?? 0}话)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                      ),
                      const Text(
                        '自动连播已开启',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  EpisodeSelectorWidget(
                    playGroups: groups,
                    currentGroupIndex: _currentGroupIndex,
                    currentEpisodeIndex: _currentEpisodeIndex,
                    onSelected: (groupIndex, epIndex) {
                      _switchEpisode(groupIndex, epIndex);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerInfoBar(
    Episode? currentEp,
    PlayGroup? currentGroup,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.video.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            [
              widget.video.year,
              currentEp?.name ?? '待播放',
            ].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              BrandPill(
                label: const Text('‹ 上一集'),
                onPressed: _currentEpisodeIndex > 0 ? _playPrevEpisode : null,
              ),
              BrandPill(
                label: const Text('下一集 ›'),
                selected: true,
                onPressed:
                    currentGroup != null &&
                        _currentEpisodeIndex + 1 < currentGroup.episodes.length
                    ? _playNextEpisode
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
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

  // 控制层
  Widget _buildControlsOverlay(Episode? currentEp, PlayGroup? currentGroup) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.75),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 顶部栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () {
                    if (_isFullscreen) {
                      _toggleFullscreen();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    '${widget.video.name} - ${currentEp?.name ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // 极光画质增强按键
                InkWell(
                  onTap: _toggleEnhance,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: _isEnhanced
                          ? AppColors.primary600
                          : Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 13,
                          color: _isEnhanced ? Colors.white : Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isEnhanced ? '极光增强' : '原画画质',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 画面比例按键
                IconButton(
                  icon: const Icon(
                    Icons.aspect_ratio_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  tooltip: '切换比例',
                  onPressed: _toggleAspectMode,
                ),

                // 线路胶囊
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    currentGroup?.server ?? '线路1',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 中间主控 (上一集 / 快退10s / 播放暂停 / 快进10s / 下一集)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 28,
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                ),
                onPressed: _currentEpisodeIndex > 0 ? _playPrevEpisode : null,
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                onPressed: () => _seekBy(-10),
              ),
              const SizedBox(width: 20),
              IconButton(
                iconSize: 52,
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_filled_rounded,
                  color: AppColors.primary500,
                ),
                onPressed: _togglePlayPause,
              ),
              const SizedBox(width: 20),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                onPressed: () => _seekBy(10),
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 28,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                onPressed:
                    (currentGroup != null &&
                        _currentEpisodeIndex + 1 < currentGroup.episodes.length)
                    ? _playNextEpisode
                    : null,
              ),
            ],
          ),

          // 底部进度条与控制行
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 全宽科技感进度条
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: AppColors.primary500,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                  thumbColor: AppColors.primary400,
                ),
                child: Slider(
                  value: _position.inMilliseconds
                      .clamp(0, _duration.inMilliseconds)
                      .toDouble(),
                  min: 0.0,
                  max:
                      (_duration.inMilliseconds > 0
                              ? _duration.inMilliseconds
                              : 1)
                          .toDouble(),
                  onChanged: (val) {
                    _player.seek(Duration(milliseconds: val.toInt()));
                    _resetHideControlsTimer();
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    // 时间指示
                    Text(
                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const Spacer(),

                    // 倍速菜单按钮
                    TextButton(
                      onPressed: () async {
                        final speed = await showBrandOptions<double>(
                          context,
                          title: '播放速度',
                          selected: _currentSpeed,
                          options: _speedList
                              .map((speed) => (speed, '${speed}x'))
                              .toList(),
                        );
                        if (speed != null && mounted) _setSpeed(speed);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(44, 36),
                      ),
                      child: Text(
                        '${_currentSpeed}x',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),

                    // 全屏选集抽屉按钮 (仅在全屏下显示)
                    if (_isFullscreen)
                      IconButton(
                        icon: const Icon(
                          Icons.playlist_play_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        tooltip: '选集',
                        onPressed: () {
                          setState(() {
                            _showFullscreenDrawer = !_showFullscreenDrawer;
                          });
                          _resetHideControlsTimer();
                        },
                      ),

                    // 全屏切换按钮
                    IconButton(
                      icon: Icon(
                        _isFullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      tooltip: _isFullscreen ? '退出全屏' : '全屏',
                      onPressed: _toggleFullscreen,
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

  // 全屏内嵌选集抽屉
  Widget _buildFullscreenDrawer(List<PlayGroup> groups) {
    final currentGroup = groups.isNotEmpty && _currentGroupIndex < groups.length
        ? groups[_currentGroupIndex]
        : null;
    final episodes = currentGroup?.episodes ?? [];

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 280,
      child: Container(
        color: const Color(0xFF0F172A).withValues(alpha: 0.95),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选集与线路',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _showFullscreenDrawer = false;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 线路切换
            SingleChildScrollView(
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

            const SizedBox(height: 12),

            // 集数网格
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.0,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: episodes.length,
                itemBuilder: (context, idx) {
                  final isPlaying = idx == _currentEpisodeIndex;
                  return InkWell(
                    onTap: () => _switchEpisode(_currentGroupIndex, idx),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isPlaying
                            ? AppColors.primary600
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        episodes[idx].name,
                        style: TextStyle(
                          color: isPlaying ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: isPlaying
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
