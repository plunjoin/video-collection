import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/models/video_model.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<http.Request> requests;
  late ApiService api;
  bool reject = false;
  int account = 1;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    reject = false;
    account = 1;
    api = ApiService.withClient(MockClient((request) async {
      requests.add(request);
      Map<String, dynamic> data = {'code': 1};
      final path = request.url.path;
      if (path == '/api/login' || path == '/api/register') {
        data.addAll({'token': 'session-$account', 'user': {'id': account, 'username': 'user$account', 'nickname': '用户$account'}});
      } else if (path == '/api/me') {
        data['data'] = {'id': account, 'username': 'user$account', 'nickname': '用户$account'};
      } else if (request.method == 'GET') {
        data['data'] = path.endsWith('favorites') && account == 1
            ? [{'video_id': 42, 'video_name': '云端番剧', 'picture': '', 'remarks': '更新中'}]
            : path.endsWith('history') && account == 1
              ? [{'video_id': 42, 'video_name': '云端番剧', 'episode_name': '第 3 话', 'route_index': 1,
                  'episode_index': 2, 'current_time': 90, 'duration': 1200, 'updated_at': '2020-01-01T00:00:00Z'}] : [];
      }
      if (reject && path.startsWith('/api/user') && request.method != 'GET') {
        return http.Response(jsonEncode({'code': 0, 'msg': '保存失败'}), 500, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(jsonEncode(data), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });

  Future<AppStateProvider> create() async {
    final state = AppStateProvider(api: api);
    while (!state.isInitialized) { await Future<void>.delayed(Duration.zero); }
    addTearDown(state.dispose);
    return state;
  }

  test('Login loads actual user, cloud favorites and playback positions; logout restores guest', () async {
    final state = await create();
    final guestVideo = VideoRecord.fromJson({'id': 7, 'name': '游客收藏'});
    await state.toggleFavorite(guestVideo);
    await state.authenticate('alice', 'password');
    expect(state.user!['nickname'], '用户1');
    expect(state.favoriteVideos.map((v) => v.id), [42]);
    expect(state.playHistory.single.currentTime, 90);
    expect(state.playHistory.single.episodeIndex, 2);
    expect(requests.where((r) => r.url.path == '/api/me').single.headers['Authorization'], 'Bearer session-1');
    expect(requests.first.headers.containsKey('Authorization'), isFalse);
    await state.logout();
    expect(state.user, isNull);
    expect(state.favoriteVideos.map((v) => v.id), [7]);
    expect(requests.last.headers['Cookie'], 'agg_auth_token=session-1');
    expect((await SharedPreferences.getInstance()).getString('account_token'), isNull);
    account = 2;
    await state.authenticate('bob', 'password', nickname: 'Bob');
    expect(state.favoriteVideos, isEmpty);
    expect(state.playHistory, isEmpty);
    expect(requests.where((r) => r.url.path == '/api/register').single.body, contains('Bob'));
  });

  test('Favorite deletion uses backend id parameter and failed writes retain local data', () async {
    final state = await create();
    await state.authenticate('alice', 'password');
    final video = state.favoriteVideos.single;
    reject = true;
    await state.toggleFavorite(video);
    expect(state.isFavorite(42), isTrue);
    expect(state.accountError, '保存失败');
    reject = false;
    await state.toggleFavorite(video);
    expect(state.isFavorite(42), isFalse);
    expect(requests.last.url.queryParameters, {'id': '42'});
    expect(requests.last.method, 'DELETE');
    await state.addPlayHistory(video: video, episodeName: '第 4 话', playerCode: 'line2', playUrl: 'example',
      routeIndex: 1, episodeIndex: 3, currentTime: 120, duration: 1200, countHit: false);
    final payload = jsonDecode(requests.last.body);
    expect(payload['current_time'], 120);
    expect(payload['route_index'], 1);
    expect(payload['episode_index'], 3);
    reject = true;
    await state.clearPlayHistory();
    expect(state.playHistory, isNotEmpty);
    reject = false;
    await state.clearPlayHistory();
    expect(state.playHistory, isEmpty);
  });

  test('Expired session returns to guest without mixing account collections', () async {
    final state = await create();
    await state.authenticate('alice', 'password');
    // A new provider restores the persisted session then validates it.
    final expired = ApiService.withClient(MockClient((request) async =>
      http.Response(jsonEncode({'code': 0, 'msg': '未登录'}), 401, headers: {'content-type': 'application/json; charset=utf-8'})));
    final restored = AppStateProvider(api: expired);
    addTearDown(restored.dispose);
    while (!restored.isInitialized || restored.syncing) { await Future<void>.delayed(Duration.zero); }
    expect(restored.isLoggedIn, isFalse);
    expect(restored.favoriteVideos, isEmpty);
    expect(restored.accountError, contains('登录已过期'));
  });

  test('Offline progress is retried on sync without reuploading cached history', () async {
    final state = await create();
    await state.authenticate('alice', 'password');
    await state.syncAccount();
    expect(requests.where((r) => r.url.path == '/api/user/history' && r.method == 'POST'), isEmpty);
    reject = true;
    await state.addPlayHistory(video: state.favoriteVideos.single, episodeName: '第 4 话',
      playerCode: 'line2', playUrl: 'example', routeIndex: 1, episodeIndex: 3,
      currentTime: 150, duration: 1200, countHit: false);
    expect(state.accountError, '保存失败');
    reject = false;
    await state.syncAccount();
    expect(state.accountError, isNull);
    expect(state.playHistory.single.currentTime, 150);
    expect(jsonDecode(requests.last.body)['current_time'], 150);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('pending_history_${Uri.encodeComponent(state.apiBaseUrl)}_1'), isEmpty);
  });
}
