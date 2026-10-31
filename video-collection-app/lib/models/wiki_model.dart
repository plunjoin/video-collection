// Wiki 知识库与 RAG 问答模型。
// 与服务端 /api/wiki/subject、/api/rag/ask 的响应结构一一对应；
// 视频详情聚合响应里的 `wiki` 字段同样使用 [WikiSubject] 解析。
library;

import 'video_model.dart';

/// 关系两端或图谱中的词条摘要。
class WikiSubjectBrief {
  final int id;
  final String name;
  final String type; // work / person / character / event / org
  final String subType; // anime / tv / movie / actor / director ...
  final String coverImage;

  const WikiSubjectBrief({
    required this.id,
    required this.name,
    required this.type,
    required this.subType,
    required this.coverImage,
  });

  bool get isWork => type == 'work';
  bool get isPerson => type == 'person';

  static WikiSubjectBrief? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    return WikiSubjectBrief(
      id: int.tryParse(raw['id']?.toString() ?? '') ?? 0,
      name: raw['name']?.toString() ?? '',
      type: raw['type']?.toString() ?? '',
      subType: raw['sub_type']?.toString() ?? '',
      coverImage: raw['cover_image']?.toString() ?? '',
    );
  }
}

/// 词条间关系（演职员、系列、纪元等）。
class WikiRelation {
  final int id;
  final int sourceId;
  final int targetId;
  final String relationType;
  final String roleDescription;
  final WikiSubjectBrief? targetSubject;
  final WikiSubjectBrief? sourceSubject;

  const WikiRelation({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relationType,
    required this.roleDescription,
    required this.targetSubject,
    required this.sourceSubject,
  });

  /// 与当前词条相对的另一端。
  WikiSubjectBrief? peerOf(int subjectId) {
    if (targetSubject != null && targetId == subjectId) return sourceSubject;
    return targetSubject;
  }

  static WikiRelation fromJson(Map<String, dynamic> json) {
    return WikiRelation(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      sourceId: int.tryParse(json['source_id']?.toString() ?? '') ?? 0,
      targetId: int.tryParse(json['target_id']?.toString() ?? '') ?? 0,
      relationType: json['relation_type']?.toString() ?? '',
      roleDescription: json['role_description']?.toString() ?? '',
      targetSubject: WikiSubjectBrief.fromJson(json['target_subject']),
      sourceSubject: WikiSubjectBrief.fromJson(json['source_subject']),
    );
  }
}

/// Wiki 词条详情（含演职员关系与关联正片）。
class WikiSubject {
  final int id;
  final String name;
  final String originalName;
  final String type;
  final String subType;
  final String summary;
  final String coverImage;
  final List<MapEntry<String, String>> infobox;
  final List<String> aliases;
  final List<WikiRelation> forwardRelations;
  final List<WikiRelation> reverseRelations;
  final List<VideoRecord> linkedVideos;

  const WikiSubject({
    required this.id,
    required this.name,
    required this.originalName,
    required this.type,
    required this.subType,
    required this.summary,
    required this.coverImage,
    required this.infobox,
    required this.aliases,
    required this.forwardRelations,
    required this.reverseRelations,
    required this.linkedVideos,
  });

  String get typeLabel => subType.isNotEmpty ? subType : type;

  /// 关系类型的展示名，与服务端语义对齐。
  static String relationLabel(String type) {
    const labels = {
      'actor': '声优 / 演员',
      'cv': '配音',
      'suit_actor': '皮套演员',
      'martial_arts': '动作指导',
      'director': '导演',
      'character_play': '饰演角色',
      'belongs_to_era': '所属纪元',
      'sequel': '系列续作',
    };
    return labels[type] ?? type;
  }

  static WikiSubject? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    String text(Object? v) => v?.toString() ?? '';

    final infobox = <MapEntry<String, String>>[];
    final rawInfobox = raw['infobox'];
    if (rawInfobox is Map) {
      rawInfobox.forEach((key, value) {
        final v = text(value).trim();
        if (key != null && v.isNotEmpty) {
          infobox.add(MapEntry(key.toString(), v));
        }
      });
    }

    final aliases = <String>[];
    if (raw['aliases'] is List) {
      for (final item in raw['aliases'] as List) {
        final a = text(item).trim();
        if (a.isNotEmpty) aliases.add(a);
      }
    }

    List<WikiRelation> relations(dynamic list) {
      final result = <WikiRelation>[];
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            result.add(
              WikiRelation.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      }
      return result;
    }

    List<VideoRecord> videos(dynamic list) {
      final result = <VideoRecord>[];
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            result.add(
              VideoRecord.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      }
      return result;
    }

    return WikiSubject(
      id: int.tryParse(raw['id']?.toString() ?? '') ?? 0,
      name: text(raw['name']),
      originalName: text(raw['original_name']),
      type: text(raw['type']),
      subType: text(raw['sub_type']),
      summary: text(raw['summary']),
      coverImage: text(raw['cover_image']),
      infobox: infobox,
      aliases: aliases,
      forwardRelations: relations(raw['forward_relations']),
      reverseRelations: relations(raw['reverse_relations']),
      linkedVideos: videos(raw['linked_videos']),
    );
  }
}

/// RAG 引用块（检索/问答共用的 citations 条目）。
class RagCitation {
  final String sourceType; // wiki_subject / wiki_relation / news / post
  final String sourceId;
  final int subjectId;
  final String text;
  final String title; // metadata.subject_name 或 metadata.title

  const RagCitation({
    required this.sourceType,
    required this.sourceId,
    required this.subjectId,
    required this.text,
    required this.title,
  });

  static RagCitation fromJson(Map<String, dynamic> json) {
    String title = '';
    final meta = json['metadata'];
    if (meta is Map) {
      title = (meta['subject_name'] ?? meta['title'])?.toString() ?? '';
    }
    return RagCitation(
      sourceType: json['source_type']?.toString() ?? '',
      sourceId: json['source_id']?.toString() ?? '',
      subjectId: int.tryParse(json['subject_id']?.toString() ?? '') ?? 0,
      text: json['text']?.toString() ?? '',
      title: title,
    );
  }
}

/// /api/rag/ask 的应答。mode 为 retrieval 时 answer 为空、note 说明降级原因。
class RagAskResult {
  final String query;
  final String answer;
  final String mode; // chat / retrieval
  final String note;
  final List<RagCitation> citations;

  const RagAskResult({
    required this.query,
    required this.answer,
    required this.mode,
    required this.note,
    required this.citations,
  });

  bool get isRetrieval => mode == 'retrieval';

  static RagAskResult? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final citations = <RagCitation>[];
    if (raw['citations'] is List) {
      for (final item in raw['citations'] as List) {
        if (item is Map) {
          citations.add(
            RagCitation.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return RagAskResult(
      query: raw['query']?.toString() ?? '',
      answer: raw['answer']?.toString() ?? '',
      mode: raw['mode']?.toString() ?? '',
      note: raw['note']?.toString() ?? '',
      citations: citations,
    );
  }
}
