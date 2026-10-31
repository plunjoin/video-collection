import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

/// 纠错对象的展示与提交上下文。
class ReportTarget {
  final String targetType; // video / news / post / wiki_subject
  final int targetId;
  final String label; // 展示用上下文，如「词条：星穹使魔物语」

  const ReportTarget({required this.targetType, required this.targetId, required this.label});
}

/// 纠错弹窗：提交到通用反馈接口（type=report，携带纠错对象上下文），
/// 管理员在后台「用户反馈」中看到对象与说明后处理。
Future<void> showReportDialog(BuildContext context, ReportTarget target) {
  return showDialog(
    context: context,
    builder: (_) => ReportDialog(target: target),
  );
}

class ReportDialog extends StatefulWidget {
  final ReportTarget target;

  const ReportDialog({super.key, required this.target});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _contentController = TextEditingController();
  final _contactController = TextEditingController();
  bool _submitting = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _contentController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiService().userRequest(
        '/api/feedback',
        method: 'POST',
        authenticated: false,
        body: {
          'type': 'report',
          'title': '【纠错】${widget.target.label}',
          'content': content,
          'contact': _contactController.text.trim(),
          'target_type': widget.target.targetType,
          'target_id': widget.target.targetId,
        },
      );
      if (!mounted) return;
      setState(() {
        _done = true;
        _submitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _submitting = false;
      });
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

    return AlertDialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(_done ? '纠错已提交 🙏' : '纠错反馈',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: _done
          ? Text(
              '感谢你的贡献，管理员会尽快核实处理。',
              style: TextStyle(fontSize: 13, color: muted),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '对象：${widget.target.label}',
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentController,
                  maxLines: 4,
                  maxLength: 500,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '请描述哪里有误，例如：演员名写错 / 剧情简介过期…',
                    hintStyle: TextStyle(fontSize: 12, color: muted),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary500),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contactController,
                  maxLength: 100,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '联系方式（选填）',
                    hintStyle: TextStyle(fontSize: 12, color: muted),
                    counterText: '',
                    isDense: true,
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
                      borderSide: const BorderSide(color: AppColors.primary500),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.rose,
                    ),
                  ),
                ],
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_done ? '知道了' : '取消',
              style: TextStyle(fontSize: 13, color: muted)),
        ),
        if (!_done)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF597BEA), Color(0xFF8B6CFF)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: (_submitting || _contentController.text.trim().isEmpty)
                  ? null
                  : _submit,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(_submitting ? '提交中...' : '提交纠错',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }
}
