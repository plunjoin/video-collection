import '../ui/kit.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../services/analytics_tracker.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../theme/brand_icons.dart';
import '../widgets/brand_controls.dart';
import 'category_screen.dart';
import 'rank_screen.dart';
import 'search_screen.dart';
import 'timeline_screen.dart';

/// 搜索发现页：热搜词、搜索历史与快捷入口聚合。
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<String> _hotWords = [];
  bool _loadingHot = true;

  @override
  void initState() {
    super.initState();
    AnalyticsTracker().screen('discover');
    _loadHotWords();
  }

  Future<void> _loadHotWords() async {
    try {
      final result = await ApiService().getSearchSuggestions();
      if (!mounted) return;
      setState(() {
        _hotWords = (result['suggestions'] as List? ?? const [])
            .whereType<String>()
            .toList();
        _loadingHot = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHot = false);
    }
  }

  void _openSearch(String keyword) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialKeyword: keyword),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? AppColors.darkBg : const Color(0xFFF7F8FD);
    final cardColor = isDark ? AppColors.darkCard : Colors.white;
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFE5E7EB);
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final app = context.watch<AppStateProvider>();
    final history = app.searchHistory;

    return Scaffold(
      backgroundColor: pageColor,
      appBar: BrandAppBar(title: const Text('发现')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 快捷入口
              Row(
                children: [
                  _entryTile(
                    context,
                    icon: BIcons.grid,
                    label: '番剧分类',
                    gradient: const [Color(0xFF80B6FF), Color(0xFF597BEA)],
                    onTap: () => _push(const CategoryScreen()),
                  ),
                  const SizedBox(width: 10),
                  _entryTile(
                    context,
                    icon: BIcons.rank,
                    label: '热度排行',
                    gradient: const [Color(0xFFFFB86C), Color(0xFFF97316)],
                    onTap: () => _push(const RankScreen()),
                  ),
                  const SizedBox(width: 10),
                  _entryTile(
                    context,
                    icon: BIcons.calendar,
                    label: '新番时间表',
                    gradient: const [Color(0xFFC4B5FD), Color(0xFF9A83FF)],
                    onTap: () => _push(const TimelineScreen()),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 热搜
              _sectionHeader('大家在搜', ink),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: _loadingHot
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: muted.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      )
                    : _hotWords.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '暂无热搜词',
                              style: TextStyle(fontSize: 12.5, color: muted),
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var i = 0; i < _hotWords.length; i++)
                                ActionChip(
                                  avatar: i < 3
                                      ? Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: i == 0
                                                ? const Color(0xFFF43F5E)
                                                : i == 1
                                                    ? const Color(0xFFF97316)
                                                    : const Color(0xFFF59E0B),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '${i + 1}',
                                            style: const TextStyle(
                                              fontSize: 9,
                                              height: 1,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      : null,
                                  backgroundColor: isDark
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFFF8FAFC),
                                  side: BorderSide(color: borderColor),
                                  label: Text(
                                    _hotWords[i],
                                    style: TextStyle(
                                        fontSize: 12.5, color: ink),
                                  ),
                                  onPressed: () => _openSearch(_hotWords[i]),
                                ),
                            ],
                          ),
              ),

              // 搜索历史
              if (history.isNotEmpty) ...[
                const SizedBox(height: 24),
                _sectionHeader('搜索历史', ink, trailing: TextButton(
                  onPressed: () async {
                    await context.read<AppStateProvider>().clearSearchHistory();
                  },
                  child: Text(
                    '清空',
                    style: TextStyle(
                      fontSize: 12,
                      color: muted,
                    ),
                  ),
                )),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final word in history)
                      ActionChip(
                        avatar: BrandIcon(
                          BIcons.history,
                          size: 14,
                          color: muted,
                          monochrome: true,
                        ),
                        backgroundColor: cardColor,
                        side: BorderSide(color: borderColor),
                        label: Text(word,
                            style: TextStyle(fontSize: 12.5, color: ink)),
                        onPressed: () => _openSearch(word),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _sectionHeader(String text, Color ink, {Widget? trailing}) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF89C7), Color(0xFF80B6FF)],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: ink),
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _entryTile(
    BuildContext context, {
    required BrandIconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : const Color(0xFFE5E7EB),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: BrandIcon(
                    icon,
                    size: 20,
                    color: Colors.white,
                    monochrome: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
