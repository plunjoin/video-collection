import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_collection_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('video queries preserve dynamic category IDs and filters', () async {
    late http.Request captured;
    final api = ApiService.withClient(
      MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'code': 1,
            'total': 1,
            'data': [
              {'id': 101, 'name': '测试番剧', 'type_id': 99},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    api.setBaseUrl('https://api.example.test');

    final result = await api.getVideos(
      typeId: 99,
      page: 2,
      pageSize: 12,
      keyword: '星之梦',
      year: '2026',
      sort: 'hits',
    );

    expect(captured.url.path, '/api/videos');
    expect(captured.url.queryParameters, {
      'page': '2',
      'page_size': '12',
      'type_id': '99',
      'keyword': '星之梦',
      'year': '2026',
      'sort': 'hits',
    });
    expect(result['total'], 1);
    expect((result['list'] as List).single.id, 101);
  });

  test('search suggestions parse remote hot words', () async {
    late http.Request captured;
    final api = ApiService.withClient(
      MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'code': 1,
            'data': {
              'keyword': '',
              'suggestions': ['作品甲', '作品乙'],
              'hot': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    api.setBaseUrl('https://api.example.test');

    final result = await api.getSearchSuggestions();

    expect(captured.url.path, '/api/search/suggest');
    expect(result['suggestions'], ['作品甲', '作品乙']);
    expect(result['hot'], isTrue);
  });

  test('personal recommendations use authenticated API response', () async {
    late http.Request captured;
    final api = ApiService.withClient(
      MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'code': 1,
            'data': {
              'items': [
                {'id': 202, 'name': '为你推荐'},
              ],
              'based_on': ['番剧'],
              'personalized': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    api.setBaseUrl('https://api.example.test');
    api.token = 'session-token';

    final result = await api.getPersonalizedRecommendations();

    expect(captured.url.path, '/api/recommend/for-you');
    expect(captured.headers['Authorization'], 'Bearer session-token');
    expect((result['list'] as List).single.id, 202);
    expect(result['personalized'], isTrue);
    expect(result['basedOn'], ['番剧']);
  });

  test('latest updates request anime and drop other types', () async {
    late http.Request captured;
    final api = ApiService.withClient(
      MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'code': 1,
            'today': [
              {'id': 1, 'name': '电影甲', 'type_id': 1, 'type_name': '电影'},
              {'id': 2, 'name': '新番乙', 'type_id': 16, 'type_name': '日韩动漫'},
            ],
            'yesterday': [
              {'id': 3, 'name': '剧集丙', 'type_id': 2, 'type_name': '电视剧'},
            ],
            'earlier': [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    api.setBaseUrl('https://api.example.test');

    final result = await api.getLatest();

    expect(captured.url.path, '/api/latest');
    expect(captured.url.queryParameters['type_id'], '4');
    expect(result['today']!.map((video) => video.id), [2]);
    expect(result['yesterday'], isEmpty);
  });

  test('video comments use the generic comments API', () async {
    final requests = <http.Request>[];
    final api = ApiService.withClient(
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'code': 1,
            'msg': '评论成功',
            'total': 1,
            'data': [
              {'id': 9, 'content': '好看'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    api.setBaseUrl('https://api.example.test');
    api.token = 'session-token';

    final listed = await api.listComments(targetType: 'video', targetId: 8);
    await api.createComment(
      targetType: 'video',
      targetId: 8,
      content: '这一集很好',
      parentId: 3,
    );
    await api.setCommentLike(commentId: 9, liked: true);

    expect(requests[0].url.path, '/api/comments');
    expect(requests[0].url.queryParameters, {
      'target_type': 'video',
      'target_id': '8',
      'page': '1',
      'page_size': '20',
    });
    expect(listed['list'].single['content'], '好看');
    expect(requests[1].method, 'POST');
    expect(jsonDecode(requests[1].body), {
      'target_type': 'video',
      'target_id': 8,
      'content': '这一集很好',
      'parent_id': 3,
    });
    expect(jsonDecode(requests[2].body), {'comment_id': 9});
  });

  test('overall and anime rankings remain separate', () async {
    final api = ApiService.withClient(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 1,
            'top': [
              {'id': 1, 'name': '全站第一'},
            ],
            'anime': [
              {'id': 2, 'name': '动漫第一'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    api.setBaseUrl('https://api.example.test');

    final result = await api.getRankings();

    expect(result['top']!.single.id, 1);
    expect(result['anime']!.single.id, 2);
  });

  test('content feed uses the news endpoint and keeps server total', () async {
    late http.Request captured;
    final api = ApiService.withClient(
      MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'code': 1,
            'total': 21,
            'data': [
              {'id': 7, 'title': '站内消息'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    api.setBaseUrl('https://api.example.test');

    final result = await api.getContentFeed(
      kind: 'news',
      page: 2,
      pageSize: 10,
    );

    expect(captured.url.path, '/api/news');
    expect(captured.url.queryParameters, {'page': '2', 'page_size': '10'});
    expect(result['total'], 21);
    expect(result['list'].single['title'], '站内消息');
  });

  test('community mutations use the documented routes and payloads', () async {
    final requests = <http.Request>[];
    final api = ApiService.withClient(
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'code': 1,
            'msg': '提交成功',
            'data': {'liked': true, 'like_count': 3},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    api.setBaseUrl('https://api.example.test');
    api.token = 'community-session';

    await api.createCommunityPost(title: '一起聊聊', content: '最近在看一部新番');
    await api.createCommunityComment(postId: 33, content: '我也喜欢这部');
    await api.setCommunityPostLike(postId: 33, liked: true);
    await api.setCommunityPostLike(postId: 33, liked: false);

    expect(requests.map((request) => request.url.path), [
      '/api/community/posts',
      '/api/community/comments',
      '/api/community/likes',
      '/api/community/likes',
    ]);
    expect(requests.map((request) => request.method), [
      'POST',
      'POST',
      'POST',
      'DELETE',
    ]);
    expect(jsonDecode(requests[0].body), {
      'title': '一起聊聊',
      'content': '最近在看一部新番',
      'category': '',
    });
    expect(jsonDecode(requests[1].body), {'post_id': 33, 'content': '我也喜欢这部'});
    expect(jsonDecode(requests[2].body), {'post_id': 33});
    expect(requests[3].url.queryParameters, {'post_id': '33'});
    expect(
      requests.every(
        (request) =>
            request.headers['Authorization'] == 'Bearer community-session',
      ),
      isTrue,
    );
  });
}
