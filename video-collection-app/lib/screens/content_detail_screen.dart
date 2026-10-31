import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/wiki_model.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../utils/responsive.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_controls.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/report_dialog.dart';
import '../widgets/video_comments.dart';
import 'account_screen.dart';
import 'anime_detail_screen.dart';
import 'wiki_subject_screen.dart';
import '../theme/brand_icons.dart';

/// 资讯 / 社区动态详情。两者共用同一套点赞与评论能力：
/// 点赞走 `/api/community/likes`，评论走 `/api/comments`（按 target_type 区分）。
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
  Map<String, dynamic>? _item;
  WikiSubject? _subject;
  bool _loading = true;
  bool _liking = false;
  int _commentTotal = 0;
  String? _error;

  bool get _isNews => widget.kind == 'news';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
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
        _commentTotal = _asInt(item['comment_count']);
        _loading = false;
      });
      // 关联了 Wiki 词条时拉取词条档案，正文前展示关联卡片。
      final subjectId = _asInt(item['subject_id']);
      if (subjectId > 0) {
        final wiki = await _api.getWikiSubject(subjectId);
        if (!mounted) return;
        setState(() => _subject = wiki?['subject'] as WikiSubject?);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _openSubject() {
    final subject = _subject;
    if (subject == null) return;
    final linkedVideo = subject.linkedVideos.isNotEmpty
        ? subject.linkedVideos.first
        : null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => linkedVideo != null && linkedVideo.id > 0
            ? AnimeDetailScreen(videoId: linkedVideo.id)
            : WikiSubjectScreen(subjectId: subject.id),
      ),
    );
  }

  // 作者显示名命中人物词条时返回，用于作者跳转（服务端按名解析）。
  WikiSubjectBrief? get _authorSubject =>
      WikiSubjectBrief.fromJson(_item?['author_subject']);

  void _openAuthor() {
    final author = _authorSubject;
    if (author == null || author.id <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WikiSubjectScreen(subjectId: author.id),
      ),
    );
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

  Widget _buildArticle(bool dark) {
    final item = _item!;
    // 桌面端不再是“手机页面投屏”：阅读宽度收窄的同时放大标题与正文
    final desktop = Responsive.isDesktop(context);
    final title = item['title']?.toString() ?? '';
    final summary = item['summary']?.toString() ?? '';
    final content = item['content']?.toString() ?? '';
    final cover = item['cover']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    final author = item['author_name']?.toString() ?? '';
    final publishedAt = _isNews ? _date(item['published_at']) : '';
    final createdAt = publishedAt.isNotEmpty
        ? publishedAt
        : _date(item['created_at']);
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

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
                style: TextStyle(
                  fontSize: desktop ? 27 : 23,
                  height: 1.45,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (author.isNotEmpty)
                    _authorSubject != null
                        ? InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _openAuthor,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    author,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: muted,
                                      decoration: TextDecoration.underline,
                                      decorationColor:
                                          muted.withValues(alpha: .5),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B6CFF)
                                          .withValues(alpha: .12),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '词条 ›',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF8B6CFF),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Text(author,
                            style: TextStyle(fontSize: 11, color: muted)),
                  if (author.isNotEmpty) const SizedBox(width: 6),
                  if (createdAt.isNotEmpty)
                    Text(createdAt,
                        style: TextStyle(fontSize: 11, color: muted)),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => showReportDialog(
                      context,
                      ReportTarget(
                        targetType: widget.kind == 'news' ? 'news' : 'post',
                        targetId: widget.contentId,
                        label: '${_isNews ? '资讯' : '动态'}：$title',
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BrandIcon(BIcons.alert,
                              size: 13, color: muted),
                          const SizedBox(width: 3),
                          Text('纠错',
                              style: TextStyle(
                                  fontSize: 11, color: muted)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (cover.isNotEmpty) ...[
                const SizedBox(height: 17),
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: CachedNetworkImage(
                    imageUrl: cover,
                    width: double.infinity,
                    height: desktop ? 340 : 220,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const _DetailCoverFallback(),
                    errorWidget: (_, _, _) => const _DetailCoverFallback(),
                  ),
                ),
              ],
              if (_subject != null) ...[
                const SizedBox(height: 14),
                _SubjectCard(subject: _subject!, onTap: _openSubject),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 17),
                Text(
                  summary,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.8,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              SelectableText(
                content,
                style: TextStyle(
                  fontSize: desktop ? 15 : 14,
                  height: desktop ? 2.0 : 1.9,
                ),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 6),
              _buildReactionBar(dark),
            ],
          ),
        ),
        _buildComments(dark),
      ],
    );
  }

  /// 点赞 / 评论动作条：像正文页脚一样安静，只有悬停才浮出一层淡底
  Widget _buildReactionBar(bool dark) {
    final item = _item!;
    final liked = item['liked'] == true;
    final line = dark ? AppColors.darkBorder : AppColors.lightBorder;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          _ReactionAction(
            icon: BIcons.heart,
            activeIcon: BIcons.heart,
            count: _asInt(item['like_count']),
            unit: '人喜欢',
            color: AppColors.rose,
            active: liked,
            onTap: _liking ? null : _toggleLike,
            tooltip: liked ? '取消点赞' : '点赞',
          ),
          Container(
            width: 1,
            height: 12,
            color: line,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          _ReactionAction(
            icon: BIcons.message,
            activeIcon: BIcons.message,
            count: _commentTotal,
            unit: '条评论',
            color: AppColors.primary500,
            active: false,
            onTap: null,
            tooltip: '评论数',
          ),
        ],
      ),
    );
  }

  Widget _buildComments(bool dark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: VideoCommentSection(
        targetType: widget.kind,
        targetId: widget.contentId,
        hintText: _isNews ? '说说你对这条资讯的看法' : '说说你的想法',
        onTotal: (total) {
          if (_commentTotal == total) return;
          setState(() => _commentTotal = total);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: BrandAppBar(title: Text(_isNews ? '资讯详情' : '动态详情')),
      body: _loading && _item == null
          ? const Center(child: BrandLoading())
          : _item == null
          ? BrandEmpty(
              title: '内容暂时不可用',
              subtitle: _error ?? '请检查网络后重试。',
              action: BrandButton(
                label: '重新加载',
                icon: BIcons.refresh,
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
    );
  }
}

/// 动作项：图标 + 数字 + 单位，平时透明，悬停浮出一层淡底
class _ReactionAction extends StatefulWidget {
  final BrandIconData icon;
  final BrandIconData activeIcon;
  final int count;
  final String unit;
  final Color color;
  final bool active;
  final VoidCallback? onTap;
  final String tooltip;

  const _ReactionAction({
    required this.icon,
    required this.activeIcon,
    required this.count,
    required this.unit,
    required this.color,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });

  @override
  State<_ReactionAction> createState() => _ReactionActionState();
}

class _ReactionActionState extends State<_ReactionAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final enabled = widget.onTap != null;
    final accent = widget.active ? widget.color : muted;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: enabled && _hovered
                  ? (dark ? const Color(0xFF26324A) : const Color(0xFFF4F7FF))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandIcon(
                  widget.active ? widget.activeIcon : widget.icon,
                  size: 17,
                  color: accent,
                  filled: widget.active,
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: widget.active ? widget.color : ink,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  widget.unit,
                  style: TextStyle(fontSize: 11, height: 1, color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 关联词条卡：资讯归属的作品 / 人物，点击进入词条档案或直接观看。
class _SubjectCard extends StatelessWidget {
  final WikiSubject subject;
  final VoidCallback onTap;

  const _SubjectCard({required this.subject, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    const violet = Color(0xFF8B6CFF);
    final linkedVideo = subject.linkedVideos.isNotEmpty
        ? subject.linkedVideos.first
        : null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: dark
                ? [const Color(0xFF3A3556), const Color(0xFF31415E)]
                : [const Color(0xFFF6F2FF), const Color(0xFFEDF3FF)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: violet.withValues(alpha: .3)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 64,
                child: subject.coverImage.isEmpty
                    ? ColoredBox(
                        color: violet.withValues(alpha: .18),
                        child: const BrandIcon(
                          BIcons.book,
                          size: 22,
                          color: violet,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: subject.coverImage,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const SizedBox(),
                        errorWidget: (_, _, _) => const SizedBox(),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '关联词条 · ${subject.typeLabel}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: violet,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subject.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subject.summary.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subject.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF597BEA), Color(0xFF8B6CFF)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                linkedVideo != null ? '去观看' : '查看',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
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
        child: const BrandIcon(
          BIcons.book,
          size: 44,
          color: AppColors.primary500,
        ),
      ),
    );
  }
}
