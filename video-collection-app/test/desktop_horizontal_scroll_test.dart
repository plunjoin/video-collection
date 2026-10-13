import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_collection_app/theme/app_theme.dart';
import 'package:video_collection_app/widgets/desktop_horizontal_scroll.dart';

void main() {
  test('vertical wheel maps onto the horizontal axis', () {
    expect(horizontalWheelDelta(AxisDirection.right, 16), 16);
    expect(horizontalWheelDelta(AxisDirection.left, 16), -16);
    expect(horizontalWheelDelta(AxisDirection.right, 0), 0);
  });

  testWidgets('theme text uses San Francisco', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            style = Theme.of(context).textTheme.bodyMedium!;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(style.fontFamily, 'SF Pro Text');
    expect(style.fontFamilyFallback, contains('PingFang SC'));
    expect(style.fontFamilyFallback, contains('Microsoft YaHei'));
  });

  testWidgets('mouse drag and wheel scroll a horizontal poster row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 120,
            child: DesktopHorizontalScroll(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 20,
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () {},
                  child: const ColoredBox(
                    color: Color(0xFF88AADD),
                    child: SizedBox(width: 120, height: 120),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    await tester.drag(
      find.byType(Scrollable),
      const Offset(-180, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(position().pixels, greaterThan(20));

    final beforeWheel = position().pixels;
    final pointer = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(200, 40)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 48)));
    await tester.pump();
    expect(position().pixels, greaterThan(beforeWheel));
  });
}
