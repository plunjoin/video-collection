/// 一起看数据模型

class WatchRoom {
  final int id;
  final String code;
  final int hostUserId;
  final int videoId;
  final int routeIndex;
  final int episodeIndex;
  final String status;
  final int maxParticipants;
  final DateTime createdAt;
  final DateTime expiresAt;

  WatchRoom({
    required this.id,
    required this.code,
    required this.hostUserId,
    required this.videoId,
    required this.routeIndex,
    required this.episodeIndex,
    required this.status,
    required this.maxParticipants,
    required this.createdAt,
    required this.expiresAt,
  });

  factory WatchRoom.fromJson(Map<String, dynamic> json) {
    return WatchRoom(
      id: json['id'] as int,
      code: json['code'] as String,
      hostUserId: json['host_user_id'] as int,
      videoId: json['video_id'] as int,
      routeIndex: json['route_index'] as int? ?? 0,
      episodeIndex: json['episode_index'] as int? ?? 0,
      status: json['status'] as String? ?? 'active',
      maxParticipants: json['max_participants'] as int? ?? 6,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  bool get isActive => status == 'active';
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class WatchParticipant {
  final int userId;
  final String username;
  final String nickname;
  final String role;

  WatchParticipant({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.role,
  });

  factory WatchParticipant.fromJson(Map<String, dynamic> json) {
    return WatchParticipant(
      userId: json['user_id'] as int,
      username: json['username'] as String,
      nickname: json['nickname'] as String,
      role: json['role'] as String,
    );
  }

  bool get isHost => role == 'host';
}

class PlaybackState {
  final bool playing;
  final int positionMs;
  final double rate;
  final int serverTsMs;
  final int revision;
  final int videoId;
  final int routeIndex;
  final int episodeIndex;
  final int hostUserId;
  final DateTime updatedAt;

  PlaybackState({
    required this.playing,
    required this.positionMs,
    required this.rate,
    required this.serverTsMs,
    required this.revision,
    required this.videoId,
    required this.routeIndex,
    required this.episodeIndex,
    required this.hostUserId,
    required this.updatedAt,
  });

  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    return PlaybackState(
      playing: json['playing'] as bool,
      positionMs: json['position_ms'] as int,
      rate: (json['rate'] as num).toDouble(),
      serverTsMs: json['server_ts_ms'] as int,
      revision: json['revision'] as int,
      videoId: json['video_id'] as int,
      routeIndex: json['route_index'] as int,
      episodeIndex: json['episode_index'] as int,
      hostUserId: json['host_user_id'] as int,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// 计算当前期望位置(考虑服务器时间戳和播放速率)
  int calculateExpectedPosition() {
    if (!playing) return positionMs;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = ((now - serverTsMs) * rate).round();
    return positionMs + elapsedMs;
  }

  /// 检查是否需要校正(返回null表示无需校正)
  DriftCorrection? checkDrift(int currentPlayerPositionMs) {
    final expected = calculateExpectedPosition();
    final diff = (currentPlayerPositionMs - expected).abs();

    const softThreshold = 400; // 400ms
    const hardThreshold = 2000; // 2s

    if (diff > hardThreshold) {
      // 硬校正:立即seek
      return DriftCorrection(
        type: CorrectionType.hard,
        targetPositionMs: expected,
      );
    } else if (diff > softThreshold) {
      // 软校正:调整播放速率追赶
      final adjustment = currentPlayerPositionMs < expected ? 1.05 : 0.95;
      return DriftCorrection(
        type: CorrectionType.soft,
        adjustedRate: rate * adjustment,
      );
    }

    return null; // 无需校正
  }
}

enum CorrectionType {
  soft, // 软校正:调整播放速率
  hard, // 硬校正:立即seek
}

class DriftCorrection {
  final CorrectionType type;
  final int? targetPositionMs;
  final double? adjustedRate;

  DriftCorrection({
    required this.type,
    this.targetPositionMs,
    this.adjustedRate,
  });
}

class RoomInfo {
  final WatchRoom room;
  final List<WatchParticipant> participants;
  final PlaybackState state;

  RoomInfo({
    required this.room,
    required this.participants,
    required this.state,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      room: WatchRoom.fromJson(json['room'] as Map<String, dynamic>),
      participants: (json['participants'] as List)
          .map((p) => WatchParticipant.fromJson(p as Map<String, dynamic>))
          .toList(),
      state: PlaybackState.fromJson(json['state'] as Map<String, dynamic>),
    );
  }

  WatchParticipant? get currentUserParticipant {
    // 需要从外部传入当前用户ID来判断
    return null;
  }
}
