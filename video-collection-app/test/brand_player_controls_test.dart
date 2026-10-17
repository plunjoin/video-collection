import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_collection_app/widgets/brand_player_controls.dart';

void main() {
  testWidgets('BrandPlayerButton triggers onPressed when enabled and ignores when null', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              BrandPlayerButton(
                icon: Icons.play_arrow_rounded,
                onPressed: () => tapped = true,
                tooltip: '播放',
              ),
              const BrandPlayerButton(
                icon: Icons.skip_next_rounded,
                onPressed: null,
                tooltip: '无下一集',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(tapped, isTrue);

    // Disabled button tap should not throw
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
  });

  testWidgets('BrandPlayerPill displays active, inactive, and custom labels', (tester) async {
    bool toggled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              BrandPlayerPill(
                label: '弹幕开',
                active: true,
                isGradient: true,
                onPressed: () => toggled = true,
              ),
              BrandPlayerPill(
                label: '1.0x',
                active: false,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('弹幕开'), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);

    await tester.tap(find.text('弹幕开'));
    await tester.pump();
    expect(toggled, isTrue);
  });

  testWidgets('BrandPlayerCenterDeck renders controls and handles play/pause and skip', (tester) async {
    bool played = false;
    int seek = 0;
    bool prev = false;
    bool next = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandPlayerCenterDeck(
            isPlaying: false,
            onTogglePlay: () => played = true,
            onPlayPrev: () => prev = true,
            onPlayNext: () => next = true,
            onSeekBackward: () => seek -= 10,
            onSeekForward: () => seek += 10,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
    expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(played, isTrue);

    await tester.tap(find.byIcon(Icons.forward_10_rounded));
    await tester.pump();
    expect(seek, 10);

    await tester.tap(find.byIcon(Icons.replay_10_rounded));
    await tester.pump();
    expect(seek, 0);

    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.pump();
    expect(prev, isTrue);

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(next, isTrue);
  });

  testWidgets('BrandPlayerTopBar shows title, badge, and interactive pills', (tester) async {
    bool routeTapped = false;
    bool enhanceTapped = false;
    bool aspectTapped = false;
    bool backTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandPlayerTopBar(
            title: '葬送的芙莉莲',
            episodeName: '第1话 冒险的结束',
            serverName: '线路1',
            isEnhanced: true,
            aspectModeLabel: '16:9',
            onBack: () => backTapped = true,
            onToggleEnhance: () => enhanceTapped = true,
            onToggleAspect: () => aspectTapped = true,
            onSelectRoute: () => routeTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('葬送的芙莉莲'), findsOneWidget);
    expect(find.text('第1话 冒险的结束'), findsOneWidget);
    expect(find.text('线路1'), findsOneWidget);
    expect(find.text('极光增强'), findsOneWidget);
    expect(find.text('16:9'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    expect(backTapped, isTrue);

    await tester.tap(find.text('极光增强'));
    await tester.pump();
    expect(enhanceTapped, isTrue);

    await tester.tap(find.text('16:9'));
    await tester.pump();
    expect(aspectTapped, isTrue);

    await tester.tap(find.text('线路1'));
    await tester.pump();
    expect(routeTapped, isTrue);
  });

  testWidgets('BrandPlayerBottomDock renders gradient slider, timestamp, and action buttons', (tester) async {
    bool danmakuToggled = false;
    bool speedSelected = false;
    bool fullscreenToggled = false;
    double? seekValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandPlayerBottomDock(
            position: const Duration(minutes: 2, seconds: 15),
            duration: const Duration(minutes: 24, seconds: 30),
            bufferProgress: 0.45,
            isPlaying: true,
            isFullscreen: false,
            danmakuEnabled: true,
            speed: 1.25,
            isCompact: false,
            formatDuration: (d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
            onSeek: (val) => seekValue = val,
            onTogglePlay: () {},
            onPlayNext: () {},
            onToggleDanmaku: () => danmakuToggled = true,
            onSelectSpeed: () => speedSelected = true,
            onToggleDrawer: () {},
            onToggleFullscreen: () => fullscreenToggled = true,
          ),
        ),
      ),
    );

    expect(find.text('2:15'), findsOneWidget);
    expect(find.text(' / 24:30'), findsOneWidget);
    expect(find.text('弹幕开'), findsOneWidget);
    expect(find.text('1.25x'), findsOneWidget);
    expect(find.text('选集'), findsOneWidget);

    // Danmaku pill tap
    await tester.tap(find.text('弹幕开'));
    await tester.pump();
    expect(danmakuToggled, isTrue);

    // Speed pill tap
    await tester.tap(find.text('1.25x'));
    await tester.pump();
    expect(speedSelected, isTrue);

    // Fullscreen button tap
    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    await tester.pump();
    expect(fullscreenToggled, isTrue);

    // Slider scrub
    final sliderFinder = find.byType(Slider);
    expect(sliderFinder, findsOneWidget);
    await tester.tap(sliderFinder);
    await tester.pump();
    expect(seekValue, isNotNull);
  });

  testWidgets('BrandPlayerScreenLock reflects lock state and handles tap', (tester) async {
    bool lockTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandPlayerScreenLock(
            isLocked: true,
            onToggleLock: () => lockTapped = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.lock_rounded));
    await tester.pump();
    expect(lockTapped, isTrue);
  });

  testWidgets('BrandPlayerHUD renders icon and feedback text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BrandPlayerHUD(
            icon: Icons.volume_up_rounded,
            text: '音量: 80%',
            progress: 0.8,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.text('音量: 80%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('BrandPlayerSpeedPanel allows dragging slider and tapping preset chips', (tester) async {
    double speed = 1.0;
    bool closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return BrandPlayerSpeedPanel(
                currentSpeed: speed,
                onSpeedChanged: (newSpeed) {
                  setState(() => speed = newSpeed);
                },
                onClose: () => closed = true,
              );
            },
          ),
        ),
      ),
    );

    // Initial state
    expect(find.text('播放倍速'), findsOneWidget);
    expect(find.text('0.5x'), findsNWidgets(2));
    expect(find.text('4.0x'), findsOneWidget);
    expect(find.text('4.0x 极速'), findsOneWidget);
    expect(find.text('1.0x 标准'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    // Tap preset chip 2.0x
    await tester.tap(find.widgetWithText(InkWell, '2.0x'));
    await tester.pumpAndSettle();
    expect(speed, 2.0);

    // Tap close button
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('BrandPlayerSpeedBoostBadge displays speed and fast forward icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BrandPlayerSpeedBoostBadge(
            speed: 2.0,
          ),
        ),
      ),
    );

    expect(find.text('2.0x 快进中'), findsOneWidget);
    expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);
  });
}

