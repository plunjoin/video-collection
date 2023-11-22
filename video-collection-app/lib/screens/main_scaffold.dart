import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/brand_widgets.dart';
import 'category_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'rank_screen.dart';
import 'search_screen.dart';
import 'timeline_screen.dart';

class MainScaffold extends StatefulWidget {
  final int initialIndex;

  const MainScaffold({super.key, this.initialIndex = 0});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  KeyEventResult _handleGlobalKeys(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final isControlOrMeta =
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      // Ctrl/Cmd + K 打开搜索
      if (isControlOrMeta && event.logicalKey == LogicalKeyboardKey.keyK) {
        _openSearch();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = Responsive.isDesktop(context);

    final screens = [
      HomeScreen(onSwitchTab: _switchTab),
      const CategoryScreen(),
      const RankScreen(),
      const TimelineScreen(),
      const ProfileScreen(),
    ];

    if (isDesktop) {
      return Focus(
        autofocus: true,
        onKeyEvent: _handleGlobalKeys,
        child: Scaffold(
          body: Column(
            children: [
              // 桌面端无边框沉浸式自定义窗口标题栏
              DesktopWindowTitleBar(isDark: isDark),

              // 主体区域：左侧侧边栏 + 右侧页面视窗
              Expanded(
                child: Row(
                  children: [
                    _buildDesktopSidebar(context, isDark),
                    Expanded(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: screens,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 移动端：保持符合拇指工学的底部导航栏
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BrandBottomNav(
        currentIndex: _currentIndex,
        onSelected: _switchTab,
      ),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context, bool isDark) {
    final appState = Provider.of<AppStateProvider>(context);

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 22, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandLogo(width: 152),
                SizedBox(height: 6),
                Text(
                  'More Stories, Together',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),

          // 桌面端快捷搜索胶囊
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: InkWell(
              onTap: _openSearch,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBg : AppColors.lightBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '搜索番剧...',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Ctrl+K',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, indent: 14, endIndent: 14),
          const SizedBox(height: 8),

          // 导航选项卡
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, '首页'),
                _buildNavItem(
                  1,
                  Icons.grid_view_rounded,
                  Icons.grid_view_sharp,
                  '番剧分类',
                ),
                _buildNavItem(
                  2,
                  Icons.emoji_events_outlined,
                  Icons.emoji_events_rounded,
                  '热度排行榜',
                ),
                _buildNavItem(
                  3,
                  Icons.calendar_month_outlined,
                  Icons.calendar_month_rounded,
                  '更新时间表',
                ),
                _buildNavItem(
                  4,
                  Icons.person_outline_rounded,
                  Icons.person_rounded,
                  '个人中心',
                ),
              ],
            ),
          ),

          // 底部工具与状态
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // 主题切换行
                InkWell(
                  onTap: () {
                    final nextMode = isDark ? ThemeMode.light : ThemeMode.dark;
                    appState.setThemeMode(nextMode);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDark
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          size: 18,
                          color: isDark
                              ? AppColors.gold
                              : Colors.amber.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isDark ? '暗夜模式' : '明亮模式',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.swap_horiz_rounded,
                          size: 16,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // 系统标识
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.emerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getPlatformLabel(),
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getPlatformLabel() {
    if (kIsWeb) return 'Web Client';
    if (Platform.isWindows) return 'Windows Desktop';
    if (Platform.isMacOS) return 'macOS Desktop';
    if (Platform.isLinux) return 'Linux Desktop';
    if (Platform.isAndroid) return 'Android Client';
    if (Platform.isIOS) return 'iOS Client';
    return 'Multi-platform';
  }

  Widget _buildNavItem(
    int index,
    IconData normalIcon,
    IconData activeIcon,
    String title,
  ) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? AppColors.primary600.withValues(alpha: isDark ? 0.2 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _switchTab(index),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isSelected ? activeIcon : normalIcon,
                  size: 20,
                  color: isSelected
                      ? AppColors.primary500
                      : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppColors.primary500
                        : (isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary),
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 4,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.primary600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
