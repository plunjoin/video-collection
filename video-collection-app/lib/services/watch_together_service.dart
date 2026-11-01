import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// 一起看成员视图。
class WatchMemberView {
  final int userId;
  final String nickname;
  final String avatar;
  final int positionMs;
  final bool isHost;

  const WatchMemberView({
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.positionMs,
    required this.isHost,
  });

  factory WatchMemberView.fromJson(Map<String, dynamic> json) {
    return WatchMemberView(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      nickname: json['nickname']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      isHost: json['is_host'] == true,
    );
  }
}

/// 一起看房间聊天消息。
class WatchMessageView {
  final int id;
  final int userId;
  final String authorName;
  final String content;
  final DateTime createdAt;

  const WatchMessageView({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  factory WatchMessageView.fromJson(Map<String, dynamic> json) {
    return WatchMessageView(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      authorName: json['author_name']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// 一起看房间快照，由服务端计算 targetPositionMs，客户端无需对时。
class WatchRoomSnapshot {
  final String code;
  final int videoId;
  final int groupIndex;
  final int episodeIndex;
  final String title;
  final int hostId;
  final int version;
  final bool playing;
  final int positionMs;
  final int anchorMs;
  final int targetPositionMs;
  final double rate;
  final bool viewerIsHost;
  final String controlMode; // host=仅房主可控制, all=所有成员可控制
  final int serverTimeMs;
  final List<WatchMemberView> members;

  const WatchRoomSnapshot({
    required this.code,
    required this.videoId,
    required this.groupIndex,
    required this.episodeIndex,
    required this.title,
    required this.hostId,
    required this.version,
    required this.playing,
    required this.positionMs,
    required this.anchorMs,
    required this.targetPositionMs,
    required this.rate,
    required this.viewerIsHost,
    required this.controlMode,
    required this.serverTimeMs,
    required this.members,
  });

  factory WatchRoomSnapshot.fromJson(Map<String, dynamic> json) {
    final members = <WatchMemberView>[];
    if (json['members'] is List) {
      for (final item in json['members'] as List) {
        if (item is Map) {
          members.add(
            WatchMemberView.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return WatchRoomSnapshot(
      code: json['code']?.toString() ?? '',
      videoId: (json['video_id'] as num?)?.toInt() ?? 0,
      groupIndex: (json['group_index'] as num?)?.toInt() ?? 0,
      episodeIndex: (json['episode_index'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      hostId: (json['host_id'] as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 0,
      playing: json['playing'] == true,
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      anchorMs: (json['anchor_ms'] as num?)?.toInt() ?? 0,
      targetPositionMs: (json['target_position_ms'] as num?)?.toInt() ?? 0,
      rate: (json['rate'] as num?)?.toDouble() ?? 1.0,
      viewerIsHost: json['viewer_is_host'] == true,
      controlMode: json['control_mode']?.toString() == 'all' ? 'all' : 'host',
      serverTimeMs: (json['server_time_ms'] as num?)?.toInt() ?? 0,
      members: members,
    );
  }
}

/// 一起看同步引擎。
///
/// 轮询模型（与弹幕一致）：成员每 2 秒心跳一次，响应携带服务端推算的
/// [WatchRoomSnapshot.targetPositionMs]；房主在本地操作时主动推送状态，
/// 心跳时做漂移校正（缓冲、卡顿导致的锚点偏差）。
class WatchTogether extends ChangeNotifier {
  final ApiService _api = ApiService();

  WatchRoomSnapshot? _snapshot;
  final List<WatchMessageView> messages = [];
  int _sinceMsgId = 0;
  Timer? _timer;
  Timer? _sseReconnectTimer;
  StreamSubscription<Map<String, dynamic>>? _sseSub;
  bool _sseConnected = false;
  int _sseGeneration = 0;
  int _sseBackoffSeconds = 3;
  bool _timerArmedHost = false;
  bool _timerArmedSse = false;
  bool _syncing = false;
  int _misses = 0;
  int _appliedVersion = 0;
  int _lastPushedVersion = 0; // 自己推送的版本，跟随逻辑跳过，避免回环
  int _serverOffsetMs = 0;
  bool _authNotified = false; // 登录过期只提示一次

  /// 当前用户 id：用于在 SSE 广播流中判定 viewer 身份（广播不带 viewer_is_host）。
  /// 为 null 时退回服务端按心跳请求判定的结果（纯轮询模式）。
  int? myUserId;

  /// 是否已加入房间。
  bool get active => _snapshot != null;

  /// 房间码。
  String? get code => _snapshot?.code;

  WatchRoomSnapshot? get snapshot => _snapshot;

  /// 当前用户是否是房主。
  bool get isHost {
    final snap = _snapshot;
    if (snap == null) return false;
    if (myUserId != null) return snap.hostId == myUserId;
    return snap.viewerIsHost;
  }

  /// 当前用户是否可以控制播放（房主，或房间开放了控制权且自己是成员）。
  bool get canControl {
    final snap = _snapshot;
    if (snap == null) return false;
    return snap.viewerIsHost || snap.controlMode == 'all';
  }

  /// 房主昵称（用于“由 XX 控制播放”提示）。
  String get hostName {
    final snap = _snapshot;
    if (snap == null) return '';
    for (final m in snap.members) {
      if (m.userId == snap.hostId) return m.nickname;
    }
    return '房主';
  }

  // ---- 播放器挂钩，由 PlayerScreen 注入 ----
  int Function() getPositionMs = () => 0;
  bool Function() isPlaying = () => false;
  int Function() getGroupIndex = () => 0;
  int Function() getEpisodeIndex = () => 0;
  double Function() getRate = () => 1.0;

  /// 应用远端状态：切集 / 播放暂停 / 拖进度 / 倍速，由播放器按最小动作执行。
  void Function(WatchRoomSnapshot snapshot) applyRemoteState = (_) {};

  /// 轻提示（HUD / SnackBar）。
  void Function(String message) showNotice = (_) {};

  /// 群聊消息到达（含自己发送的），播放器可把它送上弹幕。
  void Function(WatchMessageView message) onChatArrived = (_) {};

  /// 创建房间（建房者成为房主）。[controlMode]：host=仅房主控制，all=所有人可控制。
  /// 旧服务端不认识 control_mode 字段（严格 JSON 解码会拒绝），此时自动退回
  /// 默认的仅房主模式重试，保证建房不被版本差异卡死。
  Future<String?> create({
    required int videoId,
    required int groupIndex,
    required int episodeIndex,
    String controlMode = 'host',
  }) async {
    Future<WatchRoomSnapshot> request(String? mode) async {
      return WatchRoomSnapshot.fromJson(
        await _api.createWatchRoom(
          videoId: videoId,
          groupIndex: groupIndex,
          episodeIndex: episodeIndex,
          controlMode: mode,
        ),
      );
    }

    try {
      _activate(await request(controlMode == 'host' ? null : controlMode));
      return null;
    } on ApiException catch (error) {
      if (error.statusCode != 400 || controlMode == 'host') {
        return error.message;
      }
      // 退回旧协议重试
      try {
        _activate(await request(null));
        showNotice('当前服务端版本较旧，已按仅房主控制创建房间');
        return null;
      } on ApiException catch (retryError) {
        return retryError.message;
      } catch (_) {
        return '创建房间失败，请稍后重试';
      }
    } catch (_) {
      return '创建房间失败，请稍后重试';
    }
  }

  /// 通过房间码加入。
  Future<String?> join(String rawCode) async {
    try {
      final snap = WatchRoomSnapshot.fromJson(
        await _api.joinWatchRoom(rawCode.trim().toUpperCase()),
      );
      _activate(snap);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return '加入房间失败，请稍后重试';
    }
  }

  void _activate(WatchRoomSnapshot snap) {
    _snapshot = snap;
    _appliedVersion = 0; // 首个心跳会按房主当前状态对齐
    _lastPushedVersion = 0;
    _authNotified = false;
    messages.clear();
    _sinceMsgId = 0;
    _misses = 0;
    _startLoop();
    _connectEvents();
    notifyListeners();
  }

  /// 心跳定时器：房主是广播源，2.5 秒上报真实进度；
  /// 成员在 SSE 在线时 5 秒（保活 + 进度上报 + 漂移纠偏），回退轮询时 2 秒。
  void _setPollTimer() {
    _timer?.cancel();
    _timerArmedHost = isHost;
    _timerArmedSse = _sseConnected;
    final period = isHost
        ? const Duration(milliseconds: 2500)
        : (_sseConnected ? const Duration(seconds: 5) : const Duration(seconds: 2));
    _timer = Timer.periodic(period, (_) => _tick());
  }

  /// 房主身份或 SSE 连接状态变化后重排心跳周期。
  void _ensurePollTimer() {
    if (_timer == null) return;
    if (_timerArmedHost != isHost || _timerArmedSse != _sseConnected) {
      _setPollTimer();
    }
  }

  void _startLoop() {
    _setPollTimer();
    // 立即跑一次，加入后马上对齐房主状态。
    unawaited(_tick());
  }

  // ---- SSE 实时通道 ----

  void _connectEvents() {
    final code = _snapshot?.code;
    if (code == null || myUserId == null) return; // 未注入身份时保持纯轮询
    final generation = ++_sseGeneration;
    _sseSub?.cancel();
    _sseSub = _api.watchEvents(code).listen(
      (event) {
        if (generation != _sseGeneration || !active) return;
        _handleSseEvent(event);
        _sseBackoffSeconds = 3;
      },
      onError: (Object _) => _markSseDown(generation),
      onDone: () => _markSseDown(generation),
      cancelOnError: true,
    );
  }

  void _markSseDown(int generation) {
    if (generation != _sseGeneration || !active) return;
    if (_sseConnected) {
      _sseConnected = false;
      _setPollTimer(); // 回退 2 秒轮询
    }
    _sseReconnectTimer?.cancel();
    _sseReconnectTimer = Timer(Duration(seconds: _sseBackoffSeconds), () {
      if (generation == _sseGeneration && active) _connectEvents();
    });
    _sseBackoffSeconds = (_sseBackoffSeconds * 2).clamp(3, 30);
  }

  void _handleSseEvent(Map<String, dynamic> event) {
    switch (event['kind']) {
      case 'state':
        final raw = event['data'];
        if (raw is! Map || _snapshot == null) return;
        final snap = WatchRoomSnapshot.fromJson(
          Map<String, dynamic>.from(raw),
        );
        _absorb(snap);
        _followRemote(snap);
        break;
      case 'chat':
        final raw = event['data'];
        if (raw is Map) mergeMessages([Map<String, dynamic>.from(raw)]);
        break;
      case 'closed':
        showNotice('房间已解散');
        leave(notifyServer: false);
        break;
    }
  }

  /// 房主在本地操作后推送状态（播放 / 暂停 / 拖进度 / 切集 / 倍速）。
  /// 房间开放控制权（all）时任何成员的本地操作同样会推送。
  Future<void> pushState({
    bool? playing,
    int? positionMs,
    int? groupIndex,
    int? episodeIndex,
    double? rate,
  }) async {
    final snap = _snapshot;
    if (snap == null || !canControl) return;
    try {
      final next = WatchRoomSnapshot.fromJson(
        await _api.pushWatchState(
          snap.code,
          playing: playing,
          positionMs: positionMs,
          groupIndex: groupIndex,
          episodeIndex: episodeIndex,
          rate: rate,
        ),
      );
      _absorb(next);
      _lastPushedVersion = next.version;
    } on ApiException catch (error) {
      showNotice(error.message);
    } catch (_) {}
  }

  Future<void> _tick() async {
    final snap = _snapshot;
    if (snap == null || _syncing) return;
    _syncing = true;
    try {
      final raw = await _api.watchHeartbeat(
        code: snap.code,
        positionMs: getPositionMs(),
        sinceMsgId: _sinceMsgId,
      );
      if (raw == null) {
        _misses++;
        if (_misses == 3) showNotice('一起看连接不稳定…');
        return;
      }
      _misses = 0;
      final rawMessages = raw['messages'];
      if (rawMessages is List) {
        mergeMessages(
          rawMessages.whereType<Map>().map((item) {
            return Map<String, dynamic>.from(item);
          }).toList(),
        );
      }
      _absorb(WatchRoomSnapshot.fromJson(raw));
      if (_snapshot!.viewerIsHost) {
        await _hostCorrection();
      } else {
        _followRemote(_snapshot!);
      }
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        showNotice('房间已解散');
        await leave(notifyServer: false);
      } else if (error.statusCode == 401) {
        // 登录过期：明确告知，不再静默失联（否则成员会永远本地自播）。
        if (!_authNotified) {
          _authNotified = true;
          showNotice('登录已过期，请重新登录后一起看');
        }
      } else {
        showNotice(error.message);
      }
    } catch (_) {
      _misses++;
    } finally {
      _syncing = false;
    }
  }

  /// 成员跟随：版本变化（含切集）全量对齐；其余情况纠正播放态与进度漂移。
  /// 暂停状态下同样校正进度（服务端对暂停房间的 target 就是暂停位置），
  /// 否则「双方都暂停但位置不同」时会永远停在错误进度。
  /// 自己推送的状态（含开放控制权时成员的推送）不再重复应用。
  void _followRemote(WatchRoomSnapshot snap) {
    if (snap.version == _lastPushedVersion) {
      _appliedVersion = snap.version;
      return;
    }
    final episodeChanged =
        snap.groupIndex != getGroupIndex() ||
        snap.episodeIndex != getEpisodeIndex();
    final playStateChanged = snap.playing != isPlaying();
    final drift = snap.targetPositionMs - getPositionMs();
    if (episodeChanged ||
        snap.version != _appliedVersion ||
        playStateChanged ||
        drift.abs() > 1500) {
      if (snap.version != _appliedVersion) _appliedVersion = snap.version;
      applyRemoteState(snap);
    }
  }

  /// 房主漂移校正：实际进度偏离锚点推算超过 2.5 秒（缓冲、卡顿）时重推锚点。
  /// 推算按房主倍速换算（与服务端 TargetPositionMs 一致），
  /// 否则倍速播放时每 2.5 秒都会误判漂移、持续升版本引发成员反复硬 seek。
  Future<void> _hostCorrection() async {
    final snap = _snapshot;
    if (snap == null || !snap.playing) return;
    final serverNow =
        DateTime.now().millisecondsSinceEpoch + _serverOffsetMs;
    final rate = snap.rate > 0 ? snap.rate : 1.0;
    final expected =
        snap.positionMs + (serverNow - snap.anchorMs).clamp(0, 1 << 40) * rate;
    final actual = getPositionMs();
    if ((expected - actual).abs() > 2500) {
      await pushState(playing: isPlaying(), positionMs: actual);
    }
  }

  /// 吸收一次快照：更新房间状态并记录服务端时钟偏移（用于房主锚点推算）。
  void _absorb(WatchRoomSnapshot snap) {
    if (snap.serverTimeMs > 0) {
      _serverOffsetMs = snap.serverTimeMs - DateTime.now().millisecondsSinceEpoch;
    }
    _snapshot = snap;
    _ensurePollTimer();
    notifyListeners();
  }

  /// 心跳返回的增量消息合并入口（由 API 层拆出 messages 后调用）。
  void mergeMessages(List<Map<String, dynamic>> raw) {
    var changed = false;
    for (final item in raw) {
      final msg = WatchMessageView.fromJson(item);
      if (msg.id <= _sinceMsgId) continue;
      messages.add(msg);
      _sinceMsgId = msg.id;
      changed = true;
      onChatArrived(msg);
    }
    if (messages.length > 200) {
      messages.removeRange(0, messages.length - 200);
    }
    if (changed) notifyListeners();
  }

  /// 发送房间聊天。
  Future<String?> sendChat(String text) async {
    final snap = _snapshot;
    final content = text.trim();
    if (snap == null || content.isEmpty) return null;
    try {
      final msg = await _api.sendWatchChat(code: snap.code, content: content);
      mergeMessages([msg]);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return '发送失败，请稍后重试';
    }
  }

  /// 房主切换播放控制权限（host / all）。
  Future<String?> setControlMode(String mode) async {
    final snap = _snapshot;
    if (snap == null || !snap.viewerIsHost) return '只有房主可以修改控制权限';
    try {
      final next = WatchRoomSnapshot.fromJson(
        await _api.setWatchControlMode(code: snap.code, mode: mode),
      );
      _absorb(next);
      return null;
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return '当前服务端版本较旧，请升级服务端后使用控制权切换';
      }
      return error.message;
    } catch (_) {
      return '切换失败，请稍后重试';
    }
  }

  /// 房主转让。
  Future<String?> transferHost(int userId) async {
    final snap = _snapshot;
    if (snap == null || !snap.viewerIsHost) return '只有房主可以转让';
    try {
      final next = WatchRoomSnapshot.fromJson(
        await _api.transferWatchHost(code: snap.code, userId: userId),
      );
      _absorb(next);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return '转让失败，请稍后重试';
    }
  }

  /// 退出房间。
  Future<void> leave({bool notifyServer = true}) async {
    final snap = _snapshot;
    _teardownConnections();
    _snapshot = null;
    messages.clear();
    _sinceMsgId = 0;
    _appliedVersion = 0;
    notifyListeners();
    if (snap != null && notifyServer) {
      try {
        await _api.leaveWatchRoom(snap.code);
      } catch (_) {}
    }
  }

  void _teardownConnections() {
    _timer?.cancel();
    _timer = null;
    _sseGeneration++; // 使在途的 SSE 回调失效
    _sseSub?.cancel();
    _sseSub = null;
    _sseReconnectTimer?.cancel();
    _sseReconnectTimer = null;
    _sseConnected = false;
  }

  @override
  void dispose() {
    _teardownConnections();
    final snap = _snapshot;
    _snapshot = null;
    if (snap != null) {
      // 尽力而为地通知服务端，不阻塞退出。
      unawaited(_api.leaveWatchRoom(snap.code).catchError((Object _) {}));
    }
    super.dispose();
  }
}
