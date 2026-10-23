import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/models/video_model.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/screens/anime_detail_screen.dart';
import 'package:video_collection_app/screens/wiki_subject_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Wiki cast replaces raw credits and opens the linked subject', (tester) async {
    final state = AppStateProvider();
    addTearDown(state.dispose);
    final video = VideoRecord.fromJson({
      'id': 7, 'name': '作品', 'actor': '旧演员', 'subject_id': 21,
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(home: Scaffold(body: AnimeDetailContent(
        video: video,
        related: const [],
        cast: [WikiCastMember.fromJson({
          'subject_id': 31, 'name': '百科演员', 'relation_type': 'actor',
          'summary': 'Wiki 编辑的人物简介', 'role_description': '饰演主角',
        })],
        onPlay: (_, _) {},
        onRelated: (_) {},
      ))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('角色'));
    await tester.tap(find.text('角色'));
    await tester.pumpAndSettle();
    expect(find.text('百科演员'), findsOneWidget);
    expect(find.text('旧演员'), findsNothing);
    expect(find.text('Wiki 编辑的人物简介'), findsOneWidget);
    expect(find.text('饰演主角'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('百科演员'));
    await tester.tap(find.text('百科演员'));
    await tester.pump();
    final screen = tester.widget<WikiSubjectScreen>(find.byType(WikiSubjectScreen));
    expect(screen.subjectId, 31);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
