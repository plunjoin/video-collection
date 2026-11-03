import '../../shared/navigation/shell_chrome.dart';
import '../../shared/services/analytics_tracker.dart';
import '../../shared/ui/kit.dart';
import 'account_desktop_page.dart';
import 'category_desktop_page.dart';
import 'content_hub_desktop_page.dart';
import 'home_desktop_page.dart';
import 'profile_desktop_page.dart';
import 'rank_desktop_page.dart';
import 'search_desktop_page.dart';
import 'settings_desktop_page.dart';

class DesktopMainScaffold extends StatefulWidget {
  final ShellChromeBuilder chromeBuilder;
  final int initialIndex;

  const DesktopMainScaffold({
    super.key,
    required this.chromeBuilder,
    this.initialIndex = 0,
  });

  @override
  State<DesktopMainScaffold> createState() => _DesktopMainScaffoldState();
}

class _DesktopMainScaffoldState extends State<DesktopMainScaffold> {
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
    AnalyticsTracker()
        .screen(_pageNames[_currentIndex.clamp(0, _pageNames.length - 1)]);
  }

  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
    AnalyticsTracker()
        .screen(_pageNames[index.clamp(0, _pageNames.length - 1)]);
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchDesktopPage()));
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsDesktopPage()));
  }

  void _openAccount() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountDesktopPage()));
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ShellChrome(
      currentIndex: _currentIndex,
      onSelect: _switchTab,
      onOpenSearch: _openSearch,
      onOpenSettings: _openSettings,
      onOpenAccount: _openAccount,
    );
    final body = IndexedStack(
      index: _currentIndex,
      children: [
        HomeDesktopPage(onSwitchTab: _switchTab),
        const CategoryDesktopPage(),
        const RankDesktopPage(),
        const ContentHubDesktopPage(),
        const ProfileDesktopPage(),
      ],
    );
    return widget.chromeBuilder(context, chrome, body);
  }
}
