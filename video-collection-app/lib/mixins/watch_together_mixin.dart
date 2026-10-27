import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../models/watch_together_model.dart';
import '../services/watch_together_service.dart';

/// PlayerScreen的Watch Together集成Mixin
/// 
/// 使用方式:在PlayerScreen的State类中混入此mixin
/// 然后在适当的生命周期调用相应方法
mixin WatchTogetherMixin {
  // 需要由混入的类提供
  Player get player;
  Duration get position;
  bool get isPlaying;
  double get currentSpeed;
  int get currentGroupIndex;
  int get currentEpisodeIndex;
  
  // 需要由混入的类实现的方法
  void onSwitchEpisode(int groupIndex, int episodeIndex);
  void onShowMessage(String message);
  bool get mounted;
  void setState(VoidCallback fn);

  final _watchService = WatchTogetherService();
  
  // 状态
  RoomInfo? _roomInfo;
  bool _isInWatchTogether = false;
  bool _isDriftCorrecting = false;
  Timer? _driftCheckTimer;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _participantsSubscription;
  StreamSubscription? _errorSubscription;
  int _lastProcessedRevision = -1;

  bool get isInWatchTogether => _isInWatchTogether;
  bool get isWatchTogetherHost => _watchService.isHost;
  RoomInfo? get watchRoomInfo => _roomInfo;

  /// 初始化Watch Together(在initState中调用)
  void initWatchTogether() {
    // 监听状态更新
    _stateSubscription = _watchService.stateStream.listen(_handleStateUpdate);
    
    // 监听参与者更新
    _participantsSubscription =
        _watchService.participantsStream.listen(_handleParticipantsUpdate);
    
    // 监听错误
    _errorSubscription = _watchService.errorStream.listen((error) {
      if (mounted) {
        onShowMessage(error);
      }
    });
  }

  /// 清理Watch Together(在dispose中调用)
  void disposeWatchTogether() {
    _driftCheckTimer?.cancel();
    _stateSubscription?.cancel();
    _participantsSubscription?.cancel();
    _errorSubscription?.cancel();
    
    if (_isInWatchTogether) {
      _leaveWatchTogether();
    }
  }

  /// 创建房间
  Future<void> createWatchRoom(int videoId) async {
    try {
      final room = await _watchService.createRoom(
        videoId: videoId,
        routeIndex: currentGroupIndex,
        episodeIndex: currentEpisodeIndex,
      );

      // 加入自己创建的房间
      await _watchService.joinRoom(room.id);
      
      // 连接WebSocket
      await _watchService.connectWebSocket(room.id);

      if (mounted) {
        setState(() {
          _isInWatchTogether = true;
        });
        _startDriftCheck();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[WatchTogether] Failed to create room: $e');
      }
      if (mounted) {
        onShowMessage('创建房间失败: $e');
      }
    }
  }

  /// 加入房间
  Future<void> joinWatchRoom(RoomInfo roomInfo) async {
    try {
      _roomInfo = roomInfo;

      // 加入房间
      await _watchService.joinRoom(roomInfo.room.id);
      
      // 连接WebSocket
      await _watchService.connectWebSocket(roomInfo.room.id);

      if (mounted) {
        setState(() {
          _isInWatchTogether = true;
        });
        _startDriftCheck();

        // 如果当前视频/剧集与房间不一致,切换到房间的视频
        if (roomInfo.room.videoId != roomInfo.room.videoId ||
            currentGroupIndex != roomInfo.state.routeIndex ||
            currentEpisodeIndex != roomInfo.state.episodeIndex) {
          onSwitchEpisode(
            roomInfo.state.routeIndex,
            roomInfo.state.episodeIndex,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[WatchTogether] Failed to join room: $e');
      }
      if (mounted) {
        onShowMessage('加入房间失败: $e');
      }
    }
  }

  /// 离开房间
  Future<void> _leaveWatchTogether() async {
    _driftCheckTimer?.cancel();
    
    if (_roomInfo != null) {
      try {
        await _watchService.leaveRoom(_roomInfo!.room.id);
      } catch (e) {
        if (kDebugMode) {
          print('[WatchTogether] Failed to leave room: $e');
        }
      }
    }

    await _watchService.disconnectWebSocket();

    if (mounted) {
      setState(() {
        _isInWatchTogether = false;
        _roomInfo = null;
      });
    }
  }

  /// 处理状态更新
  void _handleStateUpdate(PlaybackState state) {
    if (!_isInWatchTogether || !mounted) return;

    // 避免重复处理同一版本
    if (state.revision <= _lastProcessedRevision) return;
    _lastProcessedRevision = state.revision;

    if (kDebugMode) {
      print('[WatchTogether] State update: revision=${state.revision}, '
          'playing=${state.playing}, position=${state.positionMs}ms');
    }

    // 如果是房主,不处理服务器状态(避免循环)
    if (_watchService.isHost) return;

    // 成员需要同步服务器状态
    _syncToServerState(state);
  }

  /// 同步到服务器状态(仅成员)
  void _syncToServerState(PlaybackState state) {
    // 检查是否需要切换剧集
    if (currentGroupIndex != state.routeIndex ||
        currentEpisodeIndex != state.episodeIndex) {
      onSwitchEpisode(state.routeIndex, state.episodeIndex);
      return; // 切换剧集会重置播放器,等待下次状态更新
    }

    // 同步播放/暂停
    if (isPlaying != state.playing) {
      if (state.playing) {
        player.play();
      } else {
        player.pause();
      }
    }

    // 同步播放速率
    if (currentSpeed != state.rate) {
      player.setRate(state.rate);
    }

    // 位置同步由drift check处理
  }

  /// 处理参与者更新
  void _handleParticipantsUpdate(List<WatchParticipant> participants) {
    if (!_isInWatchTogether || !mounted) return;

    if (kDebugMode) {
      print('[WatchTogether] Participants update: ${participants.length} members');
    }

    // 更新房间信息中的参与者列表
    if (_roomInfo != null) {
      _roomInfo = RoomInfo(
        room: _roomInfo!.room,
        participants: participants,
        state: _roomInfo!.state,
      );
      
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// 启动漂移检查
  void _startDriftCheck() {
    _driftCheckTimer?.cancel();
    _driftCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkDrift();
    });
  }

  /// 检查并修正时间漂移
  void _checkDrift() {
    if (!_isInWatchTogether || _roomInfo == null || _watchService.isHost) {
      return;
    }

    if (_isDriftCorrecting) return; // 避免重复校正

    final state = _roomInfo!.state;
    final currentPosMs = position.inMilliseconds;

    final correction = state.checkDrift(currentPosMs);
    if (correction == null) return; // 无需校正

    _isDriftCorrecting = true;

    if (correction.type == CorrectionType.hard) {
      // 硬校正:立即seek
      if (kDebugMode) {
        print('[WatchTogether] Hard correction: seek to ${correction.targetPositionMs}ms');
      }
      player.seek(Duration(milliseconds: correction.targetPositionMs!));
      
      // 短暂延迟后恢复漂移检查
      Future.delayed(const Duration(milliseconds: 500), () {
        _isDriftCorrecting = false;
      });
    } else if (correction.type == CorrectionType.soft) {
      // 软校正:临时调整播放速率
      if (kDebugMode) {
        print('[WatchTogether] Soft correction: rate=${correction.adjustedRate}');
      }
      player.setRate(correction.adjustedRate!);
      
      // 2秒后恢复正常速率
      Future.delayed(const Duration(seconds: 2), () {
        player.setRate(state.rate);
        _isDriftCorrecting = false;
      });
    }
  }

  /// 房主控制:播放
  void watchTogetherPlay() {
    if (!_isInWatchTogether || !_watchService.isHost) return;
    _watchService.play();
  }

  /// 房主控制:暂停
  void watchTogetherPause() {
    if (!_isInWatchTogether || !_watchService.isHost) return;
    _watchService.pause();
  }

  /// 房主控制:跳转
  void watchTogetherSeek(Duration position) {
    if (!_isInWatchTogether || !_watchService.isHost) return;
    _watchService.seek(position.inMilliseconds);
  }

  /// 房主控制:调速
  void watchTogetherSetRate(double rate) {
    if (!_isInWatchTogether || !_watchService.isHost) return;
    _watchService.setRate(rate);
  }

  /// 房主控制:切换剧集
  void watchTogetherSwitchEpisode(int routeIndex, int episodeIndex) {
    if (!_isInWatchTogether || !_watchService.isHost) return;
    _watchService.switchEpisode(routeIndex, episodeIndex);
  }

  /// 是否应该阻止本地控制(成员模式下)
  bool shouldBlockLocalControl() {
    return _isInWatchTogether && !_watchService.isHost;
  }

  /// 是否应该记录播放历史(一起看期间不记录)
  bool shouldRecordHistory() {
    return !_isInWatchTogether;
  }
}
