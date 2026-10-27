import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

import '../models/watch_together_model.dart';
import 'api_service.dart';

/// 一起看服务: REST + WebSocket
class WatchTogetherService {
  static final WatchTogetherService _instance =
      WatchTogetherService._internal();
  factory WatchTogetherService() => _instance;
  WatchTogetherService._internal();

  final ApiService _api = ApiService();
  WebSocketChannel? _wsChannel;
  
  // 当前房间状态
  RoomInfo? _currentRoom;
  bool _isConnected = false;
  int? _currentUserId;

  // 状态流
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _participantsController =
      StreamController<List<WatchParticipant>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<PlaybackState> get stateStream => _stateController.stream;
  Stream<List<WatchParticipant>> get participantsStream =>
      _participantsController.stream;
  Stream<String> get errorStream => _errorController.stream;

  RoomInfo? get currentRoom => _currentRoom;
  bool get isConnected => _isConnected;
  bool get isInRoom => _currentRoom != null;
  
  bool get isHost {
    if (_currentRoom == null || _currentUserId == null) return false;
    return _currentRoom!.room.hostUserId == _currentUserId;
  }

  void setCurrentUserId(int userId) {
    _currentUserId = userId;
  }

  /// 创建房间
  Future<WatchRoom> createRoom({
    required int videoId,
    required int routeIndex,
    required int episodeIndex,
  }) async {
    try {
      final response = await _api.userRequest(
        '/api/watch/rooms',
        method: 'POST',
        body: {
          'video_id': videoId,
          'route_index': routeIndex,
          'episode_index': episodeIndex,
        },
      );

      final roomData = response['data'] as Map<String, dynamic>;
      final room = WatchRoom.fromJson(roomData['room'] as Map<String, dynamic>);
      
      return room;
    } catch (e) {
      throw Exception('创建房间失败: $e');
    }
  }

  /// 根据短码获取房间信息
  Future<RoomInfo> getRoomByCode(String code) async {
    try {
      final response = await _api.userRequest(
        '/api/watch/rooms/by-code/$code',
        authenticated: false, // 公开接口
      );

      final data = response['data'] as Map<String, dynamic>;
      return RoomInfo.fromJson(data);
    } catch (e) {
      throw Exception('获取房间失败: $e');
    }
  }

  /// 加入房间
  Future<void> joinRoom(int roomId) async {
    try {
      await _api.userRequest(
        '/api/watch/rooms/$roomId/join',
        method: 'POST',
      );
    } catch (e) {
      throw Exception('加入房间失败: $e');
    }
  }

  /// 离开房间
  Future<void> leaveRoom(int roomId) async {
    try {
      await _api.userRequest(
        '/api/watch/rooms/$roomId/leave',
        method: 'POST',
      );
    } catch (e) {
      throw Exception('离开房间失败: $e');
    }
  }

  /// 连接WebSocket
  Future<void> connectWebSocket(int roomId) async {
    if (_wsChannel != null) {
      await disconnectWebSocket();
    }

    try {
      final baseUrl = _api.baseUrl;
      // 将 http(s):// 转换为 ws(s)://
      final wsUrl = baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
      final token = _api.token;
      
      final uri = Uri.parse('$wsUrl/api/watch/ws?room_id=$roomId');
      
      if (kDebugMode) {
        print('[WatchTogether] Connecting to WebSocket: $uri');
      }

      _wsChannel = WebSocketChannel.connect(uri);
      
      // 发送认证(通过query参数已传递,但某些实现可能需要额外握手)
      // 暂时先通过HTTP header传递,WebSocket连接时需要服务器支持
      
      _isConnected = true;

      // 监听消息
      _wsChannel!.stream.listen(
        _handleWebSocketMessage,
        onError: (error) {
          if (kDebugMode) {
            print('[WatchTogether] WebSocket error: $error');
          }
          _errorController.add('连接错误: $error');
          _isConnected = false;
        },
        onDone: () {
          if (kDebugMode) {
            print('[WatchTogether] WebSocket closed');
          }
          _isConnected = false;
        },
        cancelOnError: false,
      );

      // 启动心跳
      _startHeartbeat();

    } catch (e) {
      if (kDebugMode) {
        print('[WatchTogether] Failed to connect WebSocket: $e');
      }
      throw Exception('连接失败: $e');
    }
  }

  Timer? _heartbeatTimer;

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected && _wsChannel != null) {
        _sendMessage({
          'type': 'heartbeat',
          'data': {},
        });
      }
    });
  }

  /// 处理WebSocket消息
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = json.decode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String;
      final payload = data['data'] as Map<String, dynamic>;

      if (kDebugMode) {
        print('[WatchTogether] Received: $type');
      }

      switch (type) {
        case 'welcome':
          _handleWelcome(payload);
          break;
        case 'state':
          _handleState(payload);
          break;
        case 'heartbeat':
          // 心跳响应,无需处理
          break;
        default:
          if (kDebugMode) {
            print('[WatchTogether] Unknown message type: $type');
          }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[WatchTogether] Failed to parse message: $e');
      }
    }
  }

  void _handleWelcome(Map<String, dynamic> payload) {
    final state = PlaybackState.fromJson(payload['state'] as Map<String, dynamic>);
    final participants = (payload['participants'] as List)
        .map((p) => WatchParticipant.fromJson(p as Map<String, dynamic>))
        .toList();

    _stateController.add(state);
    _participantsController.add(participants);

    if (kDebugMode) {
      print('[WatchTogether] Welcome: ${participants.length} participants, revision ${state.revision}');
    }
  }

  void _handleState(Map<String, dynamic> payload) {
    final state = PlaybackState.fromJson(payload['state'] as Map<String, dynamic>);
    final participants = (payload['participants'] as List)
        .map((p) => WatchParticipant.fromJson(p as Map<String, dynamic>))
        .toList();

    _stateController.add(state);
    _participantsController.add(participants);

    if (kDebugMode) {
      print('[WatchTogether] State update: revision ${state.revision}, playing ${state.playing}, position ${state.positionMs}ms');
    }
  }

  /// 发送意图(仅房主)
  void sendIntent({
    required String action,
    int? position,
    double? rate,
    int? routeIndex,
    int? episodeIndex,
  }) {
    if (!_isConnected || _wsChannel == null) {
      _errorController.add('未连接到房间');
      return;
    }

    if (!isHost) {
      _errorController.add('只有房主可以控制播放');
      return;
    }

    final data = <String, dynamic>{
      'action': action,
    };

    if (position != null) data['position'] = position;
    if (rate != null) data['rate'] = rate;
    if (routeIndex != null) data['route_index'] = routeIndex;
    if (episodeIndex != null) data['episode_index'] = episodeIndex;

    _sendMessage({
      'type': 'intent',
      'data': data,
    });

    if (kDebugMode) {
      print('[WatchTogether] Sent intent: $action');
    }
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_wsChannel != null) {
      _wsChannel!.sink.add(json.encode(message));
    }
  }

  /// 断开WebSocket
  Future<void> disconnectWebSocket() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (_wsChannel != null) {
      await _wsChannel!.sink.close();
      _wsChannel = null;
    }

    _isConnected = false;
    _currentRoom = null;

    if (kDebugMode) {
      print('[WatchTogether] Disconnected');
    }
  }

  /// 清理资源
  void dispose() {
    disconnectWebSocket();
    _stateController.close();
    _participantsController.close();
    _errorController.close();
  }

  /// 便捷方法:播放
  void play() => sendIntent(action: 'play');

  /// 便捷方法:暂停
  void pause() => sendIntent(action: 'pause');

  /// 便捷方法:跳转
  void seek(int positionMs) => sendIntent(action: 'seek', position: positionMs);

  /// 便捷方法:调速
  void setRate(double rate) => sendIntent(action: 'rate', rate: rate);

  /// 便捷方法:切换剧集
  void switchEpisode(int routeIndex, int episodeIndex) => sendIntent(
        action: 'switch',
        routeIndex: routeIndex,
        episodeIndex: episodeIndex,
      );
}
