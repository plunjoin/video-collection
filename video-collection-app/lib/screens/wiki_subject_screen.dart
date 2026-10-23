import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/video_model.dart';
import '../services/api_service.dart';
import 'anime_detail_screen.dart';

class WikiSubjectScreen extends StatefulWidget {
  final int subjectId;
  const WikiSubjectScreen({super.key, required this.subjectId});

  @override
  State<WikiSubjectScreen> createState() => _WikiSubjectScreenState();
}

class _WikiSubjectScreenState extends State<WikiSubjectScreen> {
  WikiSubjectDetail? _subject;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final subject = await ApiService().getWikiSubject(widget.subjectId);
    if (!mounted) return;
    setState(() {
      _subject = subject;
      _loading = false;
    });
  }

  Future<void> _openSubject(WikiSubject subject) async {
    // Resolve a work's own linked videos on tap, avoiding a request per poster.
    if (subject.type == 'work') {
      final work = await ApiService().getWikiSubject(subject.id);
      if (!mounted) return;
      if (work != null && work.linkedVideos.isNotEmpty) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AnimeDetailScreen(videoId: work.linkedVideos.first.id),
        ));
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WikiSubjectScreen(subjectId: subject.id),
    ));
  }

  Widget _image(WikiSubject subject) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(subject.type == 'person' ? Icons.person : Icons.movie_outlined, size: 40)),
    );
    if (subject.coverImage.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: subject.coverImage, fit: BoxFit.cover,
      placeholder: (_, _) => fallback, errorWidget: (_, _, _) => fallback,
    );
  }

  Widget _relations(String title, List<WikiRelation> relations, {bool reverse = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (relations.isEmpty) const Text('暂无相关作品'),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720
              ? 4
              : constraints.maxWidth >= 450 ? 3 : 2;
          return Wrap(
            spacing: 12, runSpacing: 16,
            children: [for (final relation in relations)
              if ((reverse ? relation.sourceSubject : relation.targetSubject) case final WikiSubject subject)
                SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                  child: InkWell(
                    onTap: () => _openSubject(subject),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ClipRRect(borderRadius: BorderRadius.circular(12), child: AspectRatio(aspectRatio: 3 / 4, child: _image(subject))),
                      const SizedBox(height: 6),
                      Text(subject.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(relation.roleDescription.isNotEmpty ? relation.roleDescription : wikiRoleLabel(relation.relationType), style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final subject = _subject;
    return Scaffold(
      appBar: AppBar(title: Text(subject?.name ?? '百科'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: '刷新')]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : subject == null
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('未能加载词条'), TextButton(onPressed: _load, child: const Text('重新加载'))]))
        : RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 112, height: 150, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: _image(subject))),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(subject.name, style: Theme.of(context).textTheme.headlineSmall),
                      if (subject.originalName.isNotEmpty) Text(subject.originalName),
                      const SizedBox(height: 8),
                      Text('${subject.type == 'person' ? '人物' : subject.type == 'work' ? '作品' : subject.type} · ${wikiRoleLabel(subject.subType)}', style: Theme.of(context).textTheme.bodySmall),
                    ])),
                  ]),
                  const SizedBox(height: 20),
                  Text(subject.summary.isEmpty ? '暂无简介' : subject.summary.replaceAll(RegExp(r'<[^>]+>'), ''), style: const TextStyle(height: 1.7)),
                  if (subject.type == 'person')
                    _relations('相关作品', subject.reverseRelations.where((r) => r.sourceSubject?.type == 'work').toList(), reverse: true),
                  if (subject.forwardRelations.isNotEmpty)
                    _relations(subject.type == 'work' ? '演职人员与相关词条' : '相关词条', subject.forwardRelations),
                  if (subject.reverseRelations.any((r) => subject.type != 'person' || r.sourceSubject?.type != 'work'))
                    _relations('其他关联', subject.reverseRelations.where((r) => subject.type != 'person' || r.sourceSubject?.type != 'work').toList(), reverse: true),
                  if (subject.linkedVideos.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('在线观看', style: Theme.of(context).textTheme.titleLarge),
                    for (final video in subject.linkedVideos)
                      ListTile(leading: const Icon(Icons.play_circle_outline), title: Text(video.name), subtitle: Text(video.remarks), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnimeDetailScreen(videoId: video.id)))),
                  ],
                ]),
              ),
            )),
          ),
        ),
    );
  }
}
