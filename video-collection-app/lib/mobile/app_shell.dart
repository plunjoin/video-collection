/// 移动端主外壳:全屏页面 + 底部导航栏,符合拇指工学。
library;
import '../../shared/ui/kit.dart';
import 'pages/main_scaffold_mobile_page.dart';
import 'widgets/brand_bottom_nav.dart';

class MobileShell extends StatelessWidget {
  final int initialIndex;

  const MobileShell({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    return MobileMainScaffold(
      initialIndex: initialIndex,
      chromeBuilder: (context, chrome, body) {
        return Scaffold(
          body: body,
          bottomNavigationBar: BrandBottomNav(
            currentIndex: chrome.currentIndex,
            onSelected: chrome.onSelect,
          ),
        );
      },
    );
  }
}
