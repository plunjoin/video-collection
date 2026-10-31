import 'package:flutter/material.dart';

import '../models/wiki_model.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_widgets.dart';
import '../screens/content_detail_screen.dart';
import '../screens/wiki_subject_screen.dart';
import '../theme/brand_icons.dart';

/// 知识库 AI 问答底部弹层。
/// 服务端未配置对话模型时为检索模式：展示命中片段与可跳转引用。
Future<void> showRagAskSheet(BuildContext context, {String? seedQuestion}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: RagAskSheet(seedQuestion: seedQuestion),
    ),
  );
}

class RagAskSheet extends StatefulWidget {
  final String? seedQuestion;

  const RagAskSheet({super.key, this.seedQuestion});

  @override
  State<RagAskSheet> createState() => _RagAskSheetState();
}

class _RagAskSheetState extends State<RagAskSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  RagAskResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.seedQuestion != null && widget.seedQuestion!.trim().isNotEmpty) {
      _controller.text = widget.seedQuestion!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    final result = await ApiService().ragAsk(text);
    if (!mounted) return;
    setState(() {
      _result = result;
      if (result == null) _error = 'AI 服务暂时不可用，请稍后再试';
      _busy = false;
    });
  }

  void _openCitation(RagCitation citation) {
    if (citation.sourceType == 'news' || citation.sourceType == 'post') {
      final id = int.tryParse(citation.sourceId) ?? 0;
      if (id <= 0) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContentDetailScreen(
            kind: citation.sourceType,
            contentId: id,
          ),
        ),
      );
      return;
    }
    if (citation.subjectId > 0) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              WikiSubjectScreen(subjectId: citation.subjectId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final cardColor = dark ? AppColors.darkCard : Colors.white;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .82,
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const BrandIcon(BIcons.sparkles,
                    size: 18, color: Color(0xFF8B6CFF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '问问 AI 使魔',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                Text(
                  '基于站内 Wiki 与资讯',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _ask(),
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '例如：这部作品的导演是谁？',
                      hintStyle: TextStyle(fontSize: 12.5, color: muted),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primary500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _busy
                    ? const SizedBox(
                        width: 42,
                        height: 42,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppColors.primary500,
                            ),
                          ),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF597BEA), Color(0xFF8B6CFF)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: _ask,
                          icon: const BrandIcon(BIcons.arrowUp,
                              size: 18, color: Colors.white),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: _buildResult(dark, muted, ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(bool dark, Color muted, Color ink) {
    if (_busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            const BrandLoading(),
            const SizedBox(height: 10),
            Text('正在翻阅知识库...', style: TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(_error!, style: TextStyle(fontSize: 12.5, color: muted)),
      );
    }
    final result = _result;
    if (result == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '试试这样问：',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in [
                  '这部作品的导演是谁？',
                  '主角声优还演过什么？',
                  '这部作品有什么动态？',
                ])
                  ActionChip(
                    backgroundColor:
                        dark ? AppColors.darkBg : const Color(0xFFF4F6FB),
                    label: Text(
                      suggestion,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onPressed: () {
                      _controller.text = suggestion;
                      _ask();
                    },
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.isRetrieval && result.note.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              result.note,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: Color(0xFF9A6B00),
              ),
            ),
          ),
        if (result.answer.isNotEmpty) ...[
          const SizedBox(height: 10),
          SelectableText(
            result.answer,
            style: TextStyle(fontSize: 13.5, height: 1.7, color: ink),
          ),
        ],
        if (result.citations.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '知识库引用',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < result.citations.length && i < 8; i++)
                ActionChip(
                  backgroundColor:
                      dark ? AppColors.darkBg : const Color(0xFFF4F6FB),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      '[${i + 1}] ${_citationTitle(result.citations[i])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                  onPressed: () => _openCitation(result.citations[i]),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _citationTitle(RagCitation citation) {
    if (citation.title.isNotEmpty) return citation.title;
    return citation.text.isEmpty
        ? citation.sourceType
        : citation.text.substring(0, citation.text.length.clamp(0, 24));
  }
}
