import 'package:flutter_test/flutter_test.dart';

import 'package:video_collection_app/models/wiki_model.dart';

void main() {
  // 以下 JSON 结构与服务端 /api/video 聚合响应中的 wiki 字段一致。
  test('WikiSubject 解析词条、关系、属性卡与关联正片', () {
    final wiki = WikiSubject.fromJson({
      'id': 1,
      'name': '星穹使魔物语',
      'original_name': 'Starbound Familiar',
      'type': 'work',
      'sub_type': 'anime',
      'summary': '少女小满唤醒了使魔星织。',
      'cover_image': 'https://example.com/cover.png',
      'infobox': {'year': '2025', 'area': '日本', 'score': 8.7},
      'aliases': ['星穹物语', ''],
      'forward_relations': [
        {
          'id': 11,
          'source_id': 1,
          'target_id': 2,
          'relation_type': 'actor',
          'role_description': '主演',
          'target_subject': {
            'id': 2,
            'name': '花铃',
            'type': 'person',
            'sub_type': 'actor',
            'cover_image': '',
          },
        },
        {
          'id': 12,
          'source_id': 1,
          'target_id': 3,
          'relation_type': 'director',
          'role_description': '导演',
          'target_subject': {
            'id': 3,
            'name': '浅野良辅',
            'type': 'person',
            'sub_type': 'director',
            'cover_image': '',
          },
        },
      ],
      'reverse_relations': [],
      'linked_videos': [
        {
          'id': 1,
          'name': '星穹使魔物语',
          'sub_name': 'Starbound Familiar',
          'type_name': '动漫',
          'picture': 'https://example.com/cover.png',
          'year': '2025',
          'remarks': '连载中',
        },
      ],
    });

    expect(wiki, isNotNull);
    expect(wiki!.name, '星穹使魔物语');
    expect(wiki.typeLabel, 'anime');
    expect(wiki.aliases, ['星穹物语']);
    expect(wiki.infobox.length, 3);
    expect(wiki.infobox[2].value, '8.7');
    expect(wiki.forwardRelations.length, 2);
    expect(wiki.forwardRelations[0].peerOf(1)?.name, '花铃');
    expect(wiki.linkedVideos.single.name, '星穹使魔物语');

    final credits = WikiSubject.relationLabel('director');
    expect(credits, '导演');
  });

  test('WikiSubject 对 null / 非法数据安全', () {
    expect(WikiSubject.fromJson(null), isNull);
    expect(WikiSubject.fromJson('oops'), isNull);
  });

  test('RagAskResult 解析检索模式应答与引用', () {
    final result = RagAskResult.fromJson({
      'query': '星穹使魔物语的导演是谁',
      'answer': '',
      'mode': 'retrieval',
      'note': '未配置对话模型（OPENAI_API_KEY），当前为检索模式。',
      'citations': [
        {
          'id': 5,
          'source_type': 'wiki_relation',
          'source_id': '5',
          'subject_id': 4,
          'chunk_index': 0,
          'text': '词条「浅野良辅」的关系（director）：浅野良辅 → 星穹使魔物语（导演）',
          'metadata': {'subject_name': '浅野良辅', 'relation_type': 'director'},
          'similarity': 0.45,
        },
        {
          'id': 6,
          'source_type': 'news',
          'source_id': '4',
          'subject_id': 1,
          'chunk_index': 0,
          'text': '[news] 《星穹使魔物语》官宣第二季',
          'metadata': {'title': '《星穹使魔物语》官宣第二季制作决定'},
          'similarity': 0.42,
        },
      ],
    });

    expect(result, isNotNull);
    expect(result!.isRetrieval, isTrue);
    expect(result.citations.length, 2);
    expect(result.citations[0].title, '浅野良辅');
    expect(result.citations[1].title, '《星穹使魔物语》官宣第二季制作决定');
    expect(result.citations[1].subjectId, 1);
  });

  test('RagAskResult 对空数据安全', () {
    expect(RagAskResult.fromJson(null), isNull);
  });
}
