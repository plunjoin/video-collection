import '../../shared/ui/kit.dart';
import 'package:provider/provider.dart';

import '../../shared/providers/app_state_provider.dart';
import '../../shared/services/analytics_tracker.dart';
import '../../shared/services/api_service.dart';
import '../../shared/theme/brand_icons.dart';
import '../../shared/widgets/brand_controls.dart';
import './category_mobile_page.dart';
import './rank_mobile_page.dart';
import './search_mobile_page.dart';
import './timeline_mobile_page.dart';

/// 搜索发现页：热搜词、搜索历史与快捷入口聚合。
class DiscoverMobilePage extends StatefulWidget {
  const DiscoverMobilePage({super.key});

  @override
  State<DiscoverMobilePage> createState() => _DiscoverMobilePageState();
}

class _DiscoverMobilePageState extends State<DiscoverMobilePage> {
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
        builder: (_) => SearchMobilePage(initialKeyword: keyword),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.darkCard : Colors.white;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.line;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.muted;
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
                    gradient: const [AppColors.brandBlue, AppColors.brandSolid],
                    onTap: () => _push(const CategoryMobilePage()),
                  ),
                  const SizedBox(width: 10),
                  _entryTile(
                    context,
                    icon: BIcons.rank,
                    label: '热度排行',
                    gradient: const [AppColors.gold, Color(0xFFF97316)],
                    onTap: () => _push(const RankMobilePage()),
                  ),
                  const SizedBox(width: 10),
                  _entryTile(
                    context,
                    icon: BIcons.calendar,
                    label: '新番时间表',
                    gradient: const [Color(0xFFC4B5FD), AppColors.brandPurple],
                    onTap: () => _push(const TimelineMobilePage()),
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
                  borderRadius: BorderRadius.circular(AppRadius.xl),
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
                                GestureDetector(
                                  onTap: () => _openSearch(_hotWords[i]),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppColors.darkCard
                                          : const Color(0xFFF8FAFC),
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.pill),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (i < 3) ...[
                                          Container(
                                            width: 16,
                                            height: 16,
                                            alignment: Alignment.center,
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
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          _hotWords[i],
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            color: ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                      GestureDetector(
                        onTap: () => _openSearch(word),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              BrandIcon(
                                BIcons.history,
                                size: 13,
                                color: muted,
                                monochrome: true,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                word,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                        ),
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
              colors: [AppColors.brandPink, AppColors.brandBlue],
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
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.line,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: BorderRadius.circular(AppRadius.md),
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
                    color: isDark ? AppColors.darkTextPrimary : AppColors.ink,
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
