import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/responsive.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/entropy_sidebar.dart';
import '../widgets/brand_widgets.dart';
import 'account_screen.dart';
import 'category_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'rank_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'timeline_screen.dart';

class MainScaffold extends StatefulWidget {
  final int initialIndex;

  const MainScaffold({super.key, this.initialIndex = 0});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late int _currentIndex;
  double _sidebarWidth = sidebarExpandedWidth;

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
                    EntropySidebar(
                      currentIndex: _currentIndex,
                      onSelect: _switchTab,
                      onSearch: _openSearch,
                      onSettings: _openSettings,
                      onAccount: _openAccount,
                      onWidthChanged: (width) {
                        if (_sidebarWidth == width) return;
                        setState(() => _sidebarWidth = width);
                      },
                    ),
                    Expanded(
                      child: DesktopInset(
                        sidebarWidth: _sidebarWidth,
                        child: IndexedStack(
                          index: _currentIndex,
                          children: screens,
                        ),
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
}
