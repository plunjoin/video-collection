import 'package:flutter_test/flutter_test.dart';
import 'package:video_collection_app/models/watch_together_model.dart';

void main() {
  group('PlaybackState', () {
    test('calculateExpectedPosition when not playing', () {
      final state = PlaybackState(
        playing: false,
        positionMs: 5000,
        rate: 1.0,
        serverTsMs: DateTime.now().millisecondsSinceEpoch,
        revision: 1,
        videoId: 1,
        routeIndex: 0,
        episodeIndex: 0,
        hostUserId: 1,
        updatedAt: DateTime.now(),
      );

      expect(state.calculateExpectedPosition(), equals(5000));
    });

    test('calculateExpectedPosition when playing', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final state = PlaybackState(
        playing: true,
        positionMs: 5000,
        rate: 1.0,
        serverTsMs: now - 1000, // 1秒前
        revision: 1,
        videoId: 1,
        routeIndex: 0,
        episodeIndex: 0,
        hostUserId: 1,
        updatedAt: DateTime.now(),
      );

      final expected = state.calculateExpectedPosition();
      // 应该接近6000ms (5000 + 1000)
      expect(expected, greaterThan(5900));
      expect(expected, lessThan(6100));
    });

    test('checkDrift returns null for small diff (<400ms)', () {
      final state = PlaybackState(
        playing: true,
        positionMs: 5000,
        rate: 1.0,
        serverTsMs: DateTime.now().millisecondsSinceEpoch,
        revision: 1,
        videoId: 1,
        routeIndex: 0,
        episodeIndex: 0,
        hostUserId: 1,
        updatedAt: DateTime.now(),
      );

      // 差异300ms,不需要校正
      final correction = state.checkDrift(5300);
      expect(correction, isNull);
    });

    test('checkDrift returns soft correction for medium diff (400-2000ms)', () {
      final state = PlaybackState(
        playing: true,
        positionMs: 5000,
        rate: 1.0,
        serverTsMs: DateTime.now().millisecondsSinceEpoch,
        revision: 1,
        videoId: 1,
        routeIndex: 0,
        episodeIndex: 0,
        hostUserId: 1,
        updatedAt: DateTime.now(),
      );

      // 差异1000ms,需要软校正
      final correction = state.checkDrift(6000);
      expect(correction, isNotNull);
      expect(correction!.type, equals(CorrectionType.soft));
      expect(correction.adjustedRate, isNotNull);
    });

    test('checkDrift returns hard correction for large diff (>2000ms)', () {
      final state = PlaybackState(
        playing: true,
        positionMs: 5000,
        rate: 1.0,
        serverTsMs: DateTime.now().millisecondsSinceEpoch,
        revision: 1,
        videoId: 1,
        routeIndex: 0,
        episodeIndex: 0,
        hostUserId: 1,
        updatedAt: DateTime.now(),
      );

      // 差异3000ms,需要硬校正
      final correction = state.checkDrift(8000);
      expect(correction, isNotNull);
      expect(correction!.type, equals(CorrectionType.hard));
      expect(correction.targetPositionMs, isNotNull);
      expect(correction.targetPositionMs, equals(5000));
    });
  });

  group('WatchRoom', () {
    test('isActive returns true for active rooms', () {
      final room = WatchRoom(
        id: 1,
        code: 'ABC123',
        hostUserId: 1,
        videoId: 1,
        routeIndex: 0,
        episodeIndex: 0,
        status: 'active',
        maxParticipants: 6,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 4)),
      );

      expect(room.isActive, isTrue);
    });

    test('isExpired returns false for unexpired rooms', () {
      final room = WatchRoom(
        id: 1,
        code: 'ABC123',
        hostUserId: 1,
        videoId: 1,
        routeIndex: 0,
        episodeIndex: 0,
        status: 'active',
        maxParticipants: 6,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 4)),
      );

      expect(room.isExpired, isFalse);
    });

    test('isExpired returns true for expired rooms', () {
      final room = WatchRoom(
        id: 1,
        code: 'ABC123',
        hostUserId: 1,
        videoId: 1,
        routeIndex: 0,
        episodeIndex: 0,
        status: 'active',
        maxParticipants: 6,
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(room.isExpired, isTrue);
    });
  });

  group('WatchParticipant', () {
    test('isHost returns true for host role', () {
      final participant = WatchParticipant(
        userId: 1,
        username: 'user1',
        nickname: 'User One',
        role: 'host',
      );

      expect(participant.isHost, isTrue);
    });

    test('isHost returns false for member role', () {
      final participant = WatchParticipant(
        userId: 2,
        username: 'user2',
        nickname: 'User Two',
        role: 'member',
      );

      expect(participant.isHost, isFalse);
    });
  });
}
