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
import 'content_detail_screen.dart';

class ContentHubScreen extends StatefulWidget {
  const ContentHubScreen({super.key});

  @override
  State<ContentHubScreen> createState() => _ContentHubScreenState();
}

class _ContentHubScreenState extends State<ContentHubScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late final TabController _tabController;
  final List<List<Map<String, dynamic>>> _items = [[], []];
  final List<bool> _loading = [false, false];
  final List<bool> _loadingMore = [false, false];
  final List<bool> _hasMore = [false, false];
  final List<bool> _loaded = [false, false];
  final List<int> _pages = [0, 0];
  final List<String?> _errors = [null, null];
  int _activeTab = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFeed(0));
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final index = _tabController.index;
    if (_activeTab == index) return;
    _activeTab = index;
    if (!_loaded[index]) _loadFeed(index);
    if (mounted) setState(() {});
  }

  String _kind(int index) => index == 0 ? 'news' : 'post';

  Future<void> _loadFeed(int index, {bool refresh = false}) async {
    if (_loadingMore[index] || (_loading[index] && !refresh)) return;
    final page = refresh ? 1 : _pages[index] + 1;
    setState(() {
      _errors[index] = null;
      if (refresh && _items[index].isNotEmpty) {
        _loadingMore[index] = true;
      } else {
        _loading[index] = true;
      }
    });

    try {
      final result = await _api.getContentFeed(
        kind: _kind(index),
        page: page,
        pageSize: _pageSize,
      );
      final nextItems =
          (result['list'] as List<Map<String, dynamic>>?) ??
          <Map<String, dynamic>>[];
      final total = result['total'] is int
          ? result['total'] as int
          : nextItems.length;
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items[index] = nextItems;
        } else {
          final existingIds = _items[index]
              .map((item) => _intValue(item['id']))
              .toSet();
          _items[index].addAll(
            nextItems.where((item) => existingIds.add(_intValue(item['id']))),
          );
        }
        _pages[index] = page;
        _hasMore[index] = _items[index].length < total && nextItems.isNotEmpty;
        _loaded[index] = true;
        _loading[index] = false;
        _loadingMore[index] = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errors[index] = error.toString();
        _loading[index] = false;
        _loadingMore[index] = false;
      });
    }
  }

  int _intValue(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

  Future<bool> _ensureLogin() async {
    if (context.read<AppStateProvider>().isLoggedIn) return true;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountScreen()));
    return mounted && context.read<AppStateProvider>().isLoggedIn;
  }

  Future<void> _composePost() async {
    if (!await _ensureLogin() || !mounted) return;
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CommunityComposeScreen()),
    );
    if (published == true && mounted) {
      await _loadFeed(1, refresh: true);
    }
  }

  Future<void> _openDetail(int tab, Map<String, dynamic> item) async {
    final id = _intValue(item['id']);
    if (id <= 0) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ContentDetailScreen(kind: _kind(tab), contentId: id),
      ),
    );
    if (mounted && tab == 1) await _loadFeed(tab, refresh: true);
  }

  Widget _buildFeed(int index) {
    final items = _items[index];
    if (_errors[index] != null && items.isEmpty) {
      return BrandEmpty(
        title: '暂时无法连接内容服务',
        subtitle: _errors[index]!,
        action: BrandButton(
          label: '重新加载',
          icon: Icons.refresh_rounded,
          onPressed: () => _loadFeed(index, refresh: true),
        ),
      );
    }
    if (items.isEmpty && (!_loaded[index] || _loading[index])) {
      return const Center(child: BrandLoading());
    }

    final empty = items.isEmpty;
    return RefreshIndicator(
      color: AppColors.primary500,
      onRefresh: () => _loadFeed(index, refresh: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: empty ? 2 : items.length + (_hasMore[index] ? 2 : 1),
        itemBuilder: (context, position) {
          if (position == 0) {
            return BrandPageBanner(
              title: index == 0 ? '把喜欢的故事分享出来' : '和同好聊聊喜欢的作品',
              subtitle: index == 0 ? '查看站内公告、活动与番剧资讯。' : '在这里交流观后感，发现新的同好。',
              eyebrow: index == 0 ? 'BILLII · NEWS' : 'BILLII · COMMUNITY',
            );
          }
          if (empty) {
            return BrandEmpty(
              title: index == 0 ? '暂时还没有资讯' : '社区正在等你开个话题',
              subtitle: index == 0 ? '下拉刷新，稍后再来看看。' : '分享最近喜欢的作品，开启一次交流。',
              action: index == 1
                  ? BrandButton(
                      label: '发布动态',
                      icon: Icons.edit_rounded,
                      onPressed: _composePost,
                    )
                  : null,
            );
          }
          final itemIndex = position - 1;
          if (itemIndex < items.length) {
            return _ContentFeedCard(
              item: items[itemIndex],
              isNews: index == 0,
              onTap: () => _openDetail(index, items[itemIndex]),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Center(
              child: _loadingMore[index]
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : BrandButton(
                      label: '加载更多',
                      icon: Icons.expand_more_rounded,
                      onPressed: () => _loadFeed(index),
                    ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCommunity = _activeTab == 1;
    return Scaffold(
      appBar: BrandAppBar(
        title: const Text('资讯与社区'),
        bottom: BrandTabs(
          controller: _tabController,
          tabs: const [
            Tab(text: '站内资讯'),
            Tab(text: '同好社区'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildFeed(0), _buildFeed(1)],
      ),
      floatingActionButton: isCommunity
          ? FloatingActionButton.extended(
              onPressed: _composePost,
              backgroundColor: AppColors.primary600,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('发布动态'),
            )
          : null,
    );
  }
}

class _ContentFeedCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isNews;
  final VoidCallback onTap;

  const _ContentFeedCard({
    required this.item,
    required this.isNews,
    required this.onTap,
  });

  String _text(String key) => item[key]?.toString() ?? '';

  String _dateLabel() {
    final date = DateTime.tryParse(_text('created_at'))?.toLocal();
    return date == null ? '' : DateFormat('yyyy/MM/dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cover = _text('cover');
    final title = _text('title').trim().isEmpty ? '未命名内容' : _text('title');
    final author = _text('author_name');
    final category = _text('category');
    final summary = _text('summary').trim().isEmpty
        ? _text('content')
        : _text('summary');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: dark ? AppColors.darkCard : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item['pinned'] == true)
                          const _MetaPill(label: '置顶', color: AppColors.rose),
                        if (category.isNotEmpty)
                          _MetaPill(label: category, color: AppColors.purple),
                        if (isNews && category.isEmpty)
                          const _MetaPill(
                            label: '资讯',
                            color: AppColors.primary500,
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: dark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              if (author.isNotEmpty) author,
                              _dateLabel(),
                            ].where((value) => value.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: dark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                        if (!isNews) ...[
                          const Icon(
                            Icons.favorite_border_rounded,
                            size: 14,
                            color: AppColors.rose,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _text('like_count').isEmpty
                                ? '0'
                                : _text('like_count'),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 14,
                            color: AppColors.primary500,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _text('comment_count').isEmpty
                                ? '0'
                                : _text('comment_count'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (cover.isNotEmpty) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: cover,
                    width: 78,
                    height: 96,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const _CoverFallback(),
                    errorWidget: (_, _, _) => const _CoverFallback(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 78,
      height: 96,
      child: ColoredBox(
        color: dark ? AppColors.darkBg : AppColors.primary50,
        child: const Icon(
          Icons.auto_stories_rounded,
          color: AppColors.primary500,
        ),
      ),
    );
  }
}

class CommunityComposeScreen extends StatefulWidget {
  const CommunityComposeScreen({super.key});

  @override
  State<CommunityComposeScreen> createState() => _CommunityComposeScreenState();
}

class _CommunityComposeScreenState extends State<CommunityComposeScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      setState(() => _error = '标题和正文都需要填写。');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final response = await _api.createCommunityPost(
        title: title,
        content: content,
        category: _categoryController.text.trim(),
      );
      if (!mounted) return;
      final message = response['msg']?.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message?.isNotEmpty == true ? message! : '动态已提交'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: BrandAppBar(title: const Text('发布动态')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const BrandPageBanner(
              title: '把你的热爱写下来',
              subtitle: '分享观后感、作品推荐或想和同好讨论的话题。',
              eyebrow: 'SAY HELLO TO THE COMMUNITY',
            ),
            TextField(
              controller: _titleController,
              enabled: !_submitting,
              maxLength: 200,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '给这条动态起个名字',
                prefixIcon: Icon(Icons.title_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              enabled: !_submitting,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '话题分类（选填）',
                hintText: '例如：观后感、作品推荐',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              enabled: !_submitting,
              minLines: 7,
              maxLines: 14,
              maxLength: 50000,
              decoration: const InputDecoration(
                labelText: '正文',
                hintText: '写下你想分享的内容……',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Center(
              child: _submitting
                  ? const CircularProgressIndicator()
                  : BrandButton(
                      label: '提交动态',
                      icon: Icons.send_rounded,
                      onPressed: _submit,
                    ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
