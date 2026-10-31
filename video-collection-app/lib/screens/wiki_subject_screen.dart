import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/wiki_model.dart';
import '../services/api_service.dart';
import '../utils/responsive.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_controls.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/report_dialog.dart';
import 'anime_detail_screen.dart';
import 'content_detail_screen.dart';
import '../theme/brand_icons.dart';

/// Wiki 词条档案页：属性卡、关系网络、可观看正片与相关资讯。
/// 词条可以是作品，也可以是人物 / 角色 / 组织等。
class WikiSubjectScreen extends StatefulWidget {
  final int subjectId;

  const WikiSubjectScreen({super.key, required this.subjectId});

  @override
  State<WikiSubjectScreen> createState() => _WikiSubjectScreenState();
}

class _WikiSubjectScreenState extends State<WikiSubjectScreen> {
  bool _loading = true;
  WikiSubject? _subject;
  List<Map<String, dynamic>> _relatedNews = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await ApiService().getWikiSubject(widget.subjectId);
    if (!mounted) return;
    setState(() {
      _subject = result?['subject'] as WikiSubject?;
      _relatedNews =
          (result?['relatedNews'] as List<Map<String, dynamic>>?) ??
          const <Map<String, dynamic>>[];
      _loading = false;
    });
  }

  void _openSubject(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WikiSubjectScreen(subjectId: id)),
    );
  }

  void _openVideo(int videoId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailScreen(videoId: videoId)),
    );
  }

  void _openNews(Map<String, dynamic> news) {
    final id = int.tryParse(news['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContentDetailScreen(kind: 'news', contentId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? AppColors.darkBg : Colors.white,
      appBar: BrandAppBar(
        title: Text(_subject?.name ?? '词条档案'),
        actions: [
          if (_subject != null)
            IconButton(
              tooltip: '纠错',
              icon: const BrandIcon(BIcons.alert, size: 19),
              onPressed: () => showReportDialog(
                context,
                ReportTarget(
                  targetType: 'wiki_subject',
                  targetId: _subject!.id,
                  label: '词条：${_subject!.name}',
                ),
              ),
            ),
        ],
      ),
      body: _loading && _subject == null
          ? const Center(child: BrandLoading())
          : _subject == null
          ? BrandEmpty(
              title: '词条不存在或已被删除',
              subtitle: '它可能刚刚启程去往别处。',
              action: BrandButton(
                label: '重新加载',
                icon: BIcons.refresh,
                onPressed: _load,
              ),
            )
          : RefreshIndicator(
              color: AppColors.primary500,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: _headerCard(dark),
                    ),
                  ),
                  if (_subject!.forwardRelations.isNotEmpty ||
                      _subject!.reverseRelations.isNotEmpty)
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: _relationCard(dark),
                      ),
                    ),
                  if (_subject!.linkedVideos.isNotEmpty)
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: _videosCard(dark),
                      ),
                    ),
                  if (_relatedNews.isNotEmpty)
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: _newsCard(dark),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _headerCard(bool dark) {
    final subject = _subject!;
    // 桌面端窗口更大，词条档案的封面与标题相应升级一档
    final desktop = Responsive.isDesktop(context);
    final line = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final cardColor = dark ? AppColors.darkCard : Colors.white;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(desktop ? 16 : 14),
                child: SizedBox(
                  width: desktop ? 124 : 96,
                  height: desktop ? 164 : 128,
                  child: _cover(subject.coverImage, subject.name, dark),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B6CFF).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        subject.typeLabel,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8B6CFF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subject.name,
                      style: TextStyle(
                        fontSize: desktop ? 25 : 20,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subject.originalName.isNotEmpty &&
                        subject.originalName != subject.name) ...[
                      const SizedBox(height: 4),
                      Text(
                        subject.originalName,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                    if (subject.aliases.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '别名：${subject.aliases.join('、')}',
                        style: TextStyle(fontSize: 11, color: muted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (subject.summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              subject.summary,
              style: const TextStyle(fontSize: 13.5, height: 1.8),
            ),
          ],
          if (subject.infobox.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final entry in subject.infobox)
                  RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 12, color: muted),
                      children: [
                        TextSpan(text: '${entry.key}  '),
                        TextSpan(
                          text: entry.value,
                          style: TextStyle(
                            color: dark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _relationCard(bool dark) {
    final subject = _subject!;
    final line = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final cardColor = dark ? AppColors.darkCard : Colors.white;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final relations = [...subject.forwardRelations, ...subject.reverseRelations]
        .where((r) => r.peerOf(subject.id) != null)
        .toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '关系网络',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final relation in relations)
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    final peer = relation.peerOf(subject.id);
                    if (peer != null && peer.id > 0) _openSubject(peer.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: dark ? AppColors.darkBg : const Color(0xFFF4F6FB),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (relation.peerOf(subject.id)?.isPerson ??
                                    false)
                                ? const Color(0xFF8B6CFF)
                                : AppColors.primary500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          relation.peerOf(subject.id)?.name ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (relation.roleDescription.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '· ${relation.roleDescription}',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _videosCard(bool dark) {
    final line = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final cardColor = dark ? AppColors.darkCard : Colors.white;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '可观看的正片',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final video in _subject!.linkedVideos)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: video.id > 0 ? () => _openVideo(video.id) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 56,
                        height: 76,
                        child: _cover(video.picture, video.name, dark),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              video.typeName,
                              video.year,
                              video.remarks,
                            ].where((v) => v.isNotEmpty).join(' · '),
                            style: TextStyle(fontSize: 11.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                    BrandIcon(
                      BIcons.chevronRight,
                      size: 20,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _newsCard(bool dark) {
    final line = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final cardColor = dark ? AppColors.darkCard : Colors.white;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '相关资讯',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final news in _relatedNews)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openNews(news),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      news['title']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((news['summary']?.toString() ?? '').isNotEmpty)
                      Text(
                        news['summary'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cover(String url, String title, bool dark) {
    final fallback = BrandPosterFallback(title: title, forceDark: dark);
    if (url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}
