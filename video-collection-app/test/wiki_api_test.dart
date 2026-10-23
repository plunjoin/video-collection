import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_collection_app/models/video_model.dart';
import 'package:video_collection_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('video detail reads Wiki cast and retains the subject link', () async {
    final api = ApiService.withClient(MockClient((request) async {
      expect(request.url.path, '/api/video');
      expect(request.url.queryParameters['id'], '7');
      return http.Response(jsonEncode({
        'code': 1,
        'data': {'id': 7, 'name': '作品', 'subject_id': 21},
        'related': [],
        'cast': [{
          'subject_id': 31, 'name': '演员', 'type': 'person',
          'cover_image': 'https://example.com/person.jpg',
          'summary': 'Wiki 编辑简介', 'relation_type': 'actor',
          'role_description': '饰演主角', 'sort_order': 1,
        }],
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    api.setBaseUrl('https://api.example.test');
    final result = await api.getVideoDetail(7);
    final video = result['video'] as VideoRecord;
    final cast = result['cast'] as List<WikiCastMember>;
    expect(video.subjectId, 21);
    expect(VideoRecord.fromJson(video.toJson()).subjectId, 21);
    expect(cast.single.subjectId, 31);
    expect(cast.single.summary, 'Wiki 编辑简介');
    expect(cast.single.roleDescription, '饰演主角');
    expect(cast.single.coverImage, 'https://example.com/person.jpg');
  });

  test('older video details default to an empty Wiki cast', () async {
    final api = ApiService.withClient(MockClient((_) async => http.Response(
      jsonEncode({'code': 1, 'data': {'id': 7}, 'related': []}), 200,
    )));
    api.setBaseUrl('https://api.example.test');
    final result = await api.getVideoDetail(7);
    expect((result['video'] as VideoRecord).subjectId, 0);
    expect(result['cast'], isEmpty);
  });

  test('Wiki person detail parses related works and nullable collections', () async {
    final api = ApiService.withClient(MockClient((request) async {
      expect(request.url.path, '/api/wiki/subject');
      expect(request.url.queryParameters['id'], '31');
      return http.Response(jsonEncode({
        'code': 1,
        'data': {
          'id': 31, 'name': '演员', 'type': 'person', 'summary': '人物简介',
          'forward_relations': null, 'linked_videos': null,
          'reverse_relations': [{
            'id': 1, 'relation_type': 'actor', 'role_description': '饰演主角',
            'source_subject': {'id': 21, 'name': '作品', 'type': 'work', 'summary': '作品简介', 'cover_image': 'poster.jpg'},
          }],
        },
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    api.setBaseUrl('https://api.example.test');
    final person = await api.getWikiSubject(31);
    expect(person, isNotNull);
    expect(person!.summary, '人物简介');
    expect(person.reverseRelations.single.sourceSubject!.id, 21);
    expect(person.reverseRelations.single.sourceSubject!.coverImage, 'poster.jpg');
    expect(person.reverseRelations.single.roleDescription, '饰演主角');
    expect(person.forwardRelations, isEmpty);
    expect(person.linkedVideos, isEmpty);
  });

  test('missing Wiki subject returns null', () async {
    final api = ApiService.withClient(MockClient((_) async => http.Response('{}', 404)));
    api.setBaseUrl('https://api.example.test');
    expect(await api.getWikiSubject(31), isNull);
  });
}
