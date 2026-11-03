import '../../shared/navigation/shell_chrome.dart';
import '../../shared/services/analytics_tracker.dart';
import '../../shared/ui/kit.dart';
import 'account_mobile_page.dart';
import 'category_mobile_page.dart';
import 'content_hub_mobile_page.dart';
import 'home_mobile_page.dart';
import 'profile_mobile_page.dart';
import 'rank_mobile_page.dart';
import 'search_mobile_page.dart';
import 'settings_mobile_page.dart';

class MobileMainScaffold extends StatefulWidget {
  final ShellChromeBuilder chromeBuilder;
  final int initialIndex;

  const MobileMainScaffold({
    super.key,
    required this.chromeBuilder,
    this.initialIndex = 0,
  });

  @override
  State<MobileMainScaffold> createState() => _MobileMainScaffoldState();
}

class _MobileMainScaffoldState extends State<MobileMainScaffold> {
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
        .push(MaterialPageRoute(builder: (_) => const SearchMobilePage()));
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsMobilePage()));
  }

  void _openAccount() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountMobilePage()));
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
        HomeMobilePage(onSwitchTab: _switchTab),
        const CategoryMobilePage(),
        const RankMobilePage(),
        const ContentHubMobilePage(),
        const ProfileMobilePage(),
      ],
    );
    return widget.chromeBuilder(context, chrome, body);
  }
}
