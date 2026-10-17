import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_controls.dart';
import '../widgets/brand_widgets.dart';
import 'account_screen.dart';

class ContentDetailScreen extends StatefulWidget {
  final String kind;
  final int contentId;

  const ContentDetailScreen({
    super.key,
    required this.kind,
    required this.contentId,
  });

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _commentController = TextEditingController();
  Map<String, dynamic>? _item;
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _liking = false;
  bool _sendingComment = false;
  bool _loadingComments = false;
  bool _hasMoreComments = false;
  int _commentPage = 0;
  int _commentTotal = 0;
  String? _error;
  static const int _commentPageSize = 20;

  bool get _isNews => widget.kind == 'news';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  int _asInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return parsed == null ? '' : DateFormat('yyyy/MM/dd HH:mm').format(parsed);
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await _api.getContentDetail(
        kind: widget.kind,
        id: widget.contentId,
      );
      if (item.isEmpty) throw const ApiException('内容不存在或暂时不可访问');
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
      });
      if (!_isNews) await _loadComments(refresh: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadComments({bool refresh = false}) async {
    if (_isNews || _loadingComments) return;
    final page = refresh ? 1 : _commentPage + 1;
    setState(() => _loadingComments = true);
    try {
      final response = await _api.getCommunityComments(
        postId: widget.contentId,
        page: page,
        pageSize: _commentPageSize,
      );
      final items = (response['list'] as List<Map<String, dynamic>>?) ?? [];
      final total = response['total'] is int
          ? response['total'] as int
          : items.length;
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _comments = items;
        } else {
          _comments.addAll(items);
        }
        _commentPage = page;
        _commentTotal = total;
        if (_item != null) _item!['comment_count'] = total;
        _hasMoreComments = _comments.length < total && items.isNotEmpty;
        _loadingComments = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingComments = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('评论加载失败：$error')));
    }
  }

  Future<bool> _ensureLogin() async {
    if (context.read<AppStateProvider>().isLoggedIn) return true;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountScreen()));
    return mounted && context.read<AppStateProvider>().isLoggedIn;
  }

  Future<void> _toggleLike() async {
    if (_item == null || _liking || !await _ensureLogin() || !mounted) return;
    final current = _item!['liked'] == true;
    setState(() => _liking = true);
    try {
      final result = await _api.setCommunityPostLike(
        postId: widget.contentId,
        liked: !current,
      );
      final data = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _item!['liked'] = data['liked'] == true;
        _item!['like_count'] = _asInt(data['like_count']);
        _liking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _liking = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('点赞失败：$error')));
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sendingComment) return;
    if (text.length > 2000) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('评论最多 2000 字')));
      return;
    }
    if (!await _ensureLogin() || !mounted) return;
    setState(() => _sendingComment = true);
    try {
      final response = await _api.createCommunityComment(
        postId: widget.contentId,
        content: text,
      );
      if (!mounted) return;
      _commentController.clear();
      await _loadComments(refresh: true);
      if (!mounted) return;
      final message = response['msg']?.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message?.isNotEmpty == true ? message! : '评论已提交'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('评论提交失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Widget _buildComment(Map<String, dynamic> comment, bool dark) {
    final name = comment['author_name']?.toString().trim();
    final content = comment['content']?.toString() ?? '';
    final createdAt = _date(comment['created_at']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkBg : AppColors.lightBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.primary500.withValues(alpha: .13),
                child: const Icon(
                  Icons.person_rounded,
                  size: 17,
                  color: AppColors.primary600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name?.isNotEmpty == true ? name! : '同好',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                createdAt,
                style: TextStyle(
                  fontSize: 10,
                  color: dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(content, style: const TextStyle(fontSize: 13, height: 1.65)),
        ],
      ),
    );
  }

  Widget _buildArticle(bool dark) {
    final item = _item!;
    final title = item['title']?.toString() ?? '';
    final summary = item['summary']?.toString() ?? '';
    final content = item['content']?.toString() ?? '';
    final cover = item['cover']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    final author = item['author_name']?.toString() ?? '';
    final createdAt = _date(item['created_at']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrandPageBanner(
          title: category.isEmpty ? (_isNews ? '站内资讯' : '同好社区') : category,
          subtitle: _isNews ? '在这里，了解更多故事与活动。' : '每一次分享，都能遇见新的同好。',
          eyebrow: _isNews ? 'BILLII · NEWS' : 'BILLII · COMMUNITY',
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.all(18),
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
              if (item['pinned'] == true)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.rose.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '置顶内容',
                    style: TextStyle(
                      color: AppColors.rose,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.45,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                [
                  if (author.isNotEmpty) author,
                  createdAt,
                ].where((value) => value.isNotEmpty).join(' · '),
                style: TextStyle(
                  fontSize: 11,
                  color: dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              if (cover.isNotEmpty) ...[
                const SizedBox(height: 17),
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: CachedNetworkImage(
                    imageUrl: cover,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const _DetailCoverFallback(),
                    errorWidget: (_, _, _) => const _DetailCoverFallback(),
                  ),
                ),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 17),
                Text(
                  summary,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.8,
                    fontWeight: FontWeight.w600,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              SelectableText(
                content,
                style: const TextStyle(fontSize: 14, height: 1.9),
              ),
              if (!_isNews) ...[
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 7),
                Row(
                  children: [
                    IconButton(
                      onPressed: _liking ? null : _toggleLike,
                      tooltip: item['liked'] == true ? '取消喜欢' : '喜欢这条动态',
                      icon: Icon(
                        item['liked'] == true
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: AppColors.rose,
                      ),
                    ),
                    Text('${_asInt(item['like_count'])} 人喜欢'),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 17,
                      color: AppColors.primary500,
                    ),
                    const SizedBox(width: 5),
                    Text('${_asInt(item['comment_count'])} 条评论'),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (!_isNews) _buildCommentsSection(dark),
      ],
    );
  }

  Widget _buildCommentsSection(bool dark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: const EdgeInsets.all(16),
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
              const Icon(Icons.forum_rounded, color: AppColors.primary500),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '同好评论',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '$_commentTotal',
                style: TextStyle(
                  fontSize: 12,
                  color: dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          if (_comments.isEmpty && !_loadingComments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: Text(
                  '还没有评论，来做第一个分享的人吧。',
                  style: TextStyle(
                    fontSize: 12,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ),
          ..._comments.map((comment) => _buildComment(comment, dark)),
          if (_loadingComments && _comments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_hasMoreComments)
            Center(
              child: TextButton.icon(
                onPressed: _loadingComments ? null : () => _loadComments(),
                icon: const Icon(Icons.expand_more_rounded),
                label: const Text('查看更多评论'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isCommunity = !_isNews;
    return Scaffold(
      appBar: BrandAppBar(
        title: Text(_isNews ? '资讯详情' : '动态详情'),
        actions: [
          if (isCommunity)
            IconButton(
              onPressed: _liking ? null : _toggleLike,
              tooltip: _item?['liked'] == true ? '取消喜欢' : '喜欢',
              icon: Icon(
                _item?['liked'] == true
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: AppColors.rose,
              ),
            ),
        ],
      ),
      body: _loading && _item == null
          ? const Center(child: BrandLoading())
          : _item == null
          ? BrandEmpty(
              title: '内容暂时不可用',
              subtitle: _error ?? '请检查网络后重试。',
              action: BrandButton(
                label: '重新加载',
                icon: Icons.refresh_rounded,
                onPressed: _loadDetail,
              ),
            )
          : RefreshIndicator(
              color: AppColors.primary500,
              onRefresh: _loadDetail,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: _buildArticle(dark),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: isCommunity && _item != null
          ? SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
                    decoration: BoxDecoration(
                      color: dark ? AppColors.darkCard : Colors.white,
                      border: Border(
                        top: BorderSide(
                          color: dark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                    ),
                    child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        enabled: !_sendingComment,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          hintText: '友善交流，分享你的想法…',
                          counterText: '',
                          filled: true,
                          fillColor: dark
                              ? AppColors.darkBg
                              : AppColors.lightBg,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: _sendingComment ? null : _submitComment,
                      tooltip: '发送评论',
                      icon: _sendingComment
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
      : null,
    );
  }
}

class _DetailCoverFallback extends StatelessWidget {
  const _DetailCoverFallback();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      height: 220,
      child: ColoredBox(
        color: dark ? AppColors.darkBg : AppColors.primary50,
        child: const Icon(
          Icons.auto_stories_rounded,
          size: 44,
          color: AppColors.primary500,
        ),
      ),
    );
  }
}
