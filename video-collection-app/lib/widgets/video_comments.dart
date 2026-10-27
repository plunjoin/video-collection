import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../screens/account_screen.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'brand_widgets.dart';
import 'member_avatar.dart';

/// 通用评论区，对接 `/api/comments`。番剧、资讯、社区动态共用同一套交互，
/// 通过 [targetType] 区分对象（video / news / post）。
class VideoCommentSection extends StatefulWidget {
  final int targetId;
  final String targetType;
  final ValueChanged<int>? onTotal;

  /// 输入框占位文案，按内容类型区分。
  final String hintText;

  const VideoCommentSection({
    super.key,
    required this.targetId,
    this.targetType = 'video',
    this.onTotal,
    this.hintText = '说说这一集的感受',
  });

  @override
  State<VideoCommentSection> createState() => _VideoCommentSectionState();
}

class _VideoCommentSectionState extends State<VideoCommentSection> {
  final _input = TextEditingController();
  final List<Map<String, dynamic>> _comments = [];
  final Map<int, List<Map<String, dynamic>>> _replies = {};
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;
  int _replyTo = 0;
  String _replyName = '';

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  @override
  void didUpdateWidget(covariant VideoCommentSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetId != widget.targetId ||
        oldWidget.targetType != widget.targetType) {
      _comments.clear();
      _replies.clear();
      _load(refresh: true);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({required bool refresh}) async {
    if (_loadingMore) return;
    setState(() {
      if (refresh) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    final page = refresh ? 1 : _page + 1;
    try {
      final result = await ApiService().listComments(
        targetType: widget.targetType,
        targetId: widget.targetId,
        page: page,
      );
      if (!mounted) return;
      final items = List<Map<String, dynamic>>.from(result['list'] as List);
      setState(() {
        if (refresh) {
          _comments
            ..clear()
            ..addAll(items);
        } else {
          _comments.addAll(items);
        }
        _page = page;
        _total = result['total'] as int? ?? _comments.length;
        _loading = false;
        _loadingMore = false;
      });
      widget.onTotal?.call(_total);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadReplies(int rootId) async {
    try {
      final result = await ApiService().listComments(
        targetType: widget.targetType,
        targetId: widget.targetId,
        rootId: rootId,
        pageSize: 50,
      );
      if (!mounted) return;
      setState(() {
        _replies[rootId] = List<Map<String, dynamic>>.from(
          result['list'] as List,
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _requireLogin() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AccountScreen()));
  }

  Future<void> _send() async {
    final state = context.read<AppStateProvider>();
    if (!state.isLoggedIn) {
      await _requireLogin();
      return;
    }
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (text.length > 2000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('评论最多 2000 字')));
      return;
    }
    setState(() => _sending = true);
    try {
      final result = await ApiService().createComment(
        targetType: widget.targetType,
        targetId: widget.targetId,
        content: text,
        parentId: _replyTo,
      );
      if (!mounted) return;
      _input.clear();
      final parent = _replyTo;
      setState(() {
        _replyTo = 0;
        _replyName = '';
      });
      final message = result['msg']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message?.isNotEmpty == true ? message! : '评论已提交')),
      );
      if (parent > 0) {
        await _loadReplies(parent);
      }
      await _load(refresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> comment) async {
    final state = context.read<AppStateProvider>();
    if (!state.isLoggedIn) {
      await _requireLogin();
      return;
    }
    final id = _asInt(comment['id']);
    final liked = comment['liked'] == true;
    try {
      final result = await ApiService().setCommentLike(
        commentId: id,
        liked: !liked,
      );
      if (!mounted) return;
      final data = result['data'];
      setState(() {
        comment['liked'] = data is Map ? data['liked'] == true : !liked;
        if (data is Map && data['like_count'] != null) {
          comment['like_count'] = data['like_count'];
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _delete(Map<String, dynamic> comment) async {
    final id = _asInt(comment['id']);
    try {
      await ApiService().deleteComment(id);
      if (!mounted) return;
      await _load(refresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  String _when(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final userId = _asInt(context.watch<AppStateProvider>().user?['id']);
    final textColor = dark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '同好评论',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Text('$_total', style: TextStyle(color: muted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            decoration: InputDecoration(
              hintText: _replyTo > 0 ? '回复 $_replyName' : widget.hintText,
              counterText: '',
              filled: true,
              fillColor: dark ? AppColors.darkBg : AppColors.primary50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                tooltip: '发送评论',
                onPressed: _sending ? null : _send,
                icon: Icon(
                  Icons.send_rounded,
                  color: _sending ? muted : AppColors.primary500,
                ),
              ),
            ),
          ),
          if (_replyTo > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _replyTo = 0;
                  _replyName = '';
                }),
                child: const Text('取消回复'),
              ),
            ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: BrandSpinner(size: 26)),
            )
          else if (_error != null && _comments.isEmpty)
            TextButton(onPressed: () => _load(refresh: true), child: Text(_error!))
          else if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('还没有评论，来做第一个分享的人吧。', style: TextStyle(color: muted)),
            )
          else
            ..._comments.map(
              (comment) => _tile(
                comment,
                textColor: textColor,
                muted: muted,
                mine: userId > 0 && userId == _asInt(comment['user_id']),
                replies: _replies[_asInt(comment['id'])],
              ),
            ),
          if (!_loading && _comments.length < _total)
            Center(
              child: TextButton(
                onPressed: _loadingMore ? null : () => _load(refresh: false),
                child: Text(_loadingMore ? '加载中…' : '查看更多评论'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(
    Map<String, dynamic> comment, {
    required Color textColor,
    required Color muted,
    required bool mine,
    List<Map<String, dynamic>>? replies,
    bool nested = false,
  }) {
    final deleted = comment['is_deleted'] == true;
    final name = comment['author_name']?.toString().trim();
    final id = _asInt(comment['id']);
    return Padding(
      padding: EdgeInsets.only(top: 14, left: nested ? 36 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberAvatar(
            avatar: comment['author_avatar']?.toString() ?? '',
            frame: comment['author_frame']?.toString() ?? '',
            size: nested ? 28 : 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name == null || name.isEmpty ? '同好' : name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: memberColor(comment['author_color']) ?? textColor,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  deleted ? '评论已删除' : comment['content']?.toString() ?? '',
                  style: TextStyle(
                    height: 1.5,
                    color: deleted ? muted : textColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _when(comment['created_at']),
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                    if (!deleted) ...[
                      TextButton(
                        onPressed: () => _toggleLike(comment),
                        child: Text(
                          comment['liked'] == true
                              ? '已赞 ${_asInt(comment['like_count'])}'
                              : '赞 ${_asInt(comment['like_count'])}',
                        ),
                      ),
                      if (!nested)
                        TextButton(
                          onPressed: () => setState(() {
                            _replyTo = id;
                            _replyName = name == null || name.isEmpty
                                ? '同好'
                                : name;
                          }),
                          child: const Text('回复'),
                        ),
                      if (_asInt(comment['reply_count']) > 0 && replies == null)
                        TextButton(
                          onPressed: () => _loadReplies(id),
                          child: Text('${_asInt(comment['reply_count'])} 条回复'),
                        ),
                      if (mine)
                        TextButton(
                          onPressed: () => _delete(comment),
                          child: const Text('删除'),
                        ),
                    ],
                  ],
                ),
                if (replies != null)
                  ...replies.map(
                    (reply) => _tile(
                      reply,
                      textColor: textColor,
                      muted: muted,
                      mine: false,
                      nested: true,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
