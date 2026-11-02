import '../ui/kit.dart';
import 'package:flutter/services.dart';

import '../services/analytics_tracker.dart';
import '../utils/responsive.dart';
import '../widgets/desktop_side_rail.dart';
import '../widgets/brand_widgets.dart';
import 'account_screen.dart';
import 'category_screen.dart';
import 'content_hub_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'rank_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class MainScaffold extends StatefulWidget {
  final int initialIndex;

  const MainScaffold({super.key, this.initialIndex = 0});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late int _currentIndex;

  static const List<String> _pageNames = [
    'home',
    'category',
    'rank',
    'news',
    'profile',
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    AnalyticsTracker().screen(_pageNames[_currentIndex.clamp(0, _pageNames.length - 1)]);
  }

  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
    AnalyticsTracker().screen(_pageNames[index.clamp(0, _pageNames.length - 1)]);
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openAccount() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountScreen()));
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
    final isDesktop = Responsive.isDesktop(context);

    final screens = [
      HomeScreen(onSwitchTab: _switchTab),
      const CategoryScreen(),
      const RankScreen(),
      const ContentHubScreen(),
      const ProfileScreen(),
    ];

    if (isDesktop) {
      return Focus(
        autofocus: true,
        onKeyEvent: _handleGlobalKeys,
        child: Scaffold(
          // Dart 自绘标题栏已完全移除：右上角为 windows/runner 原生实现的
          // 最小化/最大化/关闭按钮；窗口拖拽由页面标题栏承担。
          body: Row(
            children: [
              DesktopSideRail(
                currentIndex: _currentIndex,
                onSelect: _switchTab,
                onSettings: _openSettings,
                onAccount: _openAccount,
              ),
              Expanded(
                child: DesktopInset(
                  sidebarWidth: sidebarExpandedWidth,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: screens,
                  ),
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
}
