// 品牌图标目检板：把全部 BIcons 渲染成 PNG，人工核对几何是否走样。
// 运行：flutter test test/brand_icons_golden_test.dart --update-goldens
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_collection_app/theme/brand_icons.dart';

List<(String, BrandIconData)> _iconEntries() {
  final data = <String, BrandIconData>{
    'home': BIcons.home,
    'search': BIcons.search,
    'calendar': BIcons.calendar,
    'rank': BIcons.rank,
    'library': BIcons.library,
    'bookmark': BIcons.bookmark,
    'heart': BIcons.heart,
    'star': BIcons.star,
    'bell': BIcons.bell,
    'user': BIcons.user,
    'history': BIcons.history,
    'logout': BIcons.logout,
    'play': BIcons.play,
    'pause': BIcons.pause,
    'prev': BIcons.prev,
    'next': BIcons.next,
    'arrowLeft': BIcons.arrowLeft,
    'arrowRight': BIcons.arrowRight,
    'chevronDown': BIcons.chevronDown,
    'check': BIcons.check,
    'plus': BIcons.plus,
    'close': BIcons.close,
    'shuffle': BIcons.shuffle,
    'sparkles': BIcons.sparkles,
    'smile': BIcons.smile,
    'compass': BIcons.compass,
    'moon': BIcons.moon,
    'ratio': BIcons.ratio,
    'routes': BIcons.routes,
    'episodes': BIcons.episodes,
    'repeat': BIcons.repeat,
    'volume': BIcons.volume,
    'muted': BIcons.muted,
    'fullscreen': BIcons.fullscreen,
    'message': BIcons.message,
    'mail': BIcons.mail,
    'link': BIcons.link,
    'lock': BIcons.lock,
    'settings': BIcons.settings,
    'speed': BIcons.speed,
    'arrowUp': BIcons.arrowUp,
    'chevronLeft': BIcons.chevronLeft,
    'chevronRight': BIcons.chevronRight,
    'chevronUp': BIcons.chevronUp,
    'refresh': BIcons.refresh,
    'alert': BIcons.alert,
    'download': BIcons.download,
    'book': BIcons.book,
    'trash': BIcons.trash,
    'fastForward': BIcons.fastForward,
    'rewind': BIcons.rewind,
    'medal': BIcons.medal,
    'trophy': BIcons.trophy,
    'sidebar': BIcons.sidebar,
    'send': BIcons.send,
    'playCircle': BIcons.playCircle,
    'share': BIcons.share,
    'forum': BIcons.forum,
    'edit': BIcons.edit,
    'checkCircle': BIcons.checkCircle,
    'cancel': BIcons.cancel,
    'news': BIcons.news,
    'notes': BIcons.notes,
    'arrowDown': BIcons.arrowDown,
    'arrowUpRight': BIcons.arrowUpRight,
    'thumbUp': BIcons.thumbUp,
    'subtitles': BIcons.subtitles,
    'gamepad': BIcons.gamepad,
    'tag': BIcons.tag,
    'rocket': BIcons.rocket,
    'flame': BIcons.flame,
    'minus': BIcons.minus,
    'square': BIcons.square,
    'restore': BIcons.restore,
    'sun': BIcons.sun,
    'keyboard': BIcons.keyboard,
    'image': BIcons.image,
    'quote': BIcons.quote,
    'flag': BIcons.flag,
    'fit': BIcons.fit,
    'hanger': BIcons.hanger,
    'ban': BIcons.ban,
    'badge': BIcons.badge,
    'volumeLow': BIcons.volumeLow,
    'login': BIcons.login,
    'live': BIcons.live,
    'grid': BIcons.grid,
    'playlist': BIcons.playlist,
    'title': BIcons.title,
    'unlock': BIcons.unlock,
    'fullscreenExit': BIcons.fullscreenExit,
  };
  final entries = data.entries.toList();
  entries.sort((a, b) => a.key.compareTo(b.key));
  return [for (final e in entries) (e.key, e.value)];
}

class _Board extends StatelessWidget {
  final List<(String, BrandIconData)> entries;
  const _Board({required this.entries});

  @override
  Widget build(BuildContext context) {
    const columns = 5;
    const cellWidth = 170.0;
    const cellHeight = 110.0;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox(
        width: columns * cellWidth + 16,
        height: ((entries.length / columns).ceil() * cellHeight) + 16,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: GridView.count(
            crossAxisCount: columns,
            childAspectRatio: cellWidth / cellHeight,
            physics: const NeverScrollableScrollPhysics(),
            children: [
            for (final (name, data) in entries)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        BrandIcon(data,
                            size: 44, color: const Color(0xFF438FF0)),
                        const SizedBox(width: 14),
                        BrandIcon(
                          data,
                          size: 44,
                          color: const Color(0xFF353B58),
                          filled: true,
                          monochrome: true,
                        ),
                        const SizedBox(width: 14),
                        BrandIcon(data, size: 22, color: const Color(0xFF7D899B)),
                      ],
                    ),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 6, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('brand icons render boards', (tester) async {
    final entries = _iconEntries();
    const perBoard = 30;
    const columns = 5;
    final boards = (entries.length / perBoard).ceil();

    for (var b = 0; b < boards; b++) {
      final chunk = entries.sublist(
        b * perBoard,
        math.min((b + 1) * perBoard, entries.length),
      );
      final rows = (chunk.length / columns).ceil();
      await tester.binding
          .setSurfaceSize(Size(columns * 170 + 16, rows * 110 + 16));

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(useMaterial3: true),
          home: _Board(entries: chunk),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(_Board),
        matchesGoldenFile('goldens/brand_icons_board_${b + 1}.png'),
      );
      final file = File('test/goldens/brand_icons_board_${b + 1}.png');
      if (file.existsSync()) {
        stdout.writeln('board ${b + 1} written: ${file.path}');
      }
    }
  });
}
