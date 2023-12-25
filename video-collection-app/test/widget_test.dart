import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/main.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => AppStateProvider())],
        child: const BlliiApp(),
      ),
    );

    // Initial pump
    await tester.pump();
    expect(find.byType(BlliiApp), findsOneWidget);
  });
}
