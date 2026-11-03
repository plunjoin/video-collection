import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/desktop/desktop_app.dart';
import 'package:video_collection_app/shared/app_bootstrap.dart';
import 'package:video_collection_app/shared/providers/app_state_provider.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => AppStateProvider())],
        child: const DesktopBlliiApp(launchArgs: AppLaunchArgs()),
      ),
    );

    // Initial pump
    await tester.pump();
    expect(find.byType(DesktopBlliiApp), findsOneWidget);
  });
}
