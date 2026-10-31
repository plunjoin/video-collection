// bllii 品牌 UI 图标库。
//
// 图标与 bllii-brand-kit/ui-icons.html 一一对应：24×24 视窗、1.8 圆润笔画、
// 圆头圆角，右上或角落缀一道 #FF89C7 粉色「速度短线」。品牌库里没有的
// 图标按同一套几何语言补齐（见标注 `扩展` 的条目）。
//
// 用法：`BrandIcon(BIcons.play, size: 20)`，颜色/尺寸缺省时继承 [IconTheme]，
// 可以像 Icon 一样放进 IconButton / Row / const 上下文。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 品牌点缀色：速度短线专属粉。
const Color kBrandIconAccent = Color(0xFFFF89C7);

/// 一条笔画。`d` 为 SVG path 数据；`color` 缺省跟随图标主色，
/// 传入则强制使用（用于复刻 kit 里带专属色的笔画）。
class BrandPath {
  final String d;
  final double width;
  final Color? color;
  const BrandPath(this.d, {this.width = 1.8, this.color});
}

/// 一个品牌图标的几何定义。
class BrandIconData {
  final String name;

  /// 主笔画，绘制为 [BrandIcon.color]（缺省继承 IconTheme）。
  final List<BrandPath> paths;

  /// 粉色点缀笔画（速度短线）；[BrandIcon.monochrome] 时改用主色。
  final List<String> accents;

  const BrandIconData(this.name, {required this.paths, this.accents = const []});

  @override
  String toString() => 'BIcons.$name';
}

/// bllii 功能图标集。
abstract final class BIcons {
  // ---------------------------------------------------------------------------
  // 与 bllii-brand-kit/ui-icons.html 完全一致的图标
  // ---------------------------------------------------------------------------
  static const home = BrandIconData('home', paths: [
    BrandPath('m3 11 7-7q2-2 4 0l7 7M5 10v9q0 2 2 2h10q2 0 2-2v-9M10 21v-7h4v7'),
  ], accents: [
    'M17 4h3v3',
  ]);
  static const search = BrandIconData('search', paths: [
    BrandPath('M17 10.5a6.5 6.5 0 1 1-13 0 6.5 6.5 0 0 1 13 0Z'),
    BrandPath('m15.5 15.5 5 5M7.5 9q1-2 3-2'),
  ], accents: [
    'M19 4h2M20 3v2',
  ]);
  static const calendar = BrandIconData('calendar', paths: [
    BrandPath('M8 9v8q0 4 4 4h8q4 0 4-4V9q0-4-4-4H8Q4 5 4 9Z'),
    BrandPath('M8 3v4m8-4v4M4 10h16M8 14h2m-2 3h2m4-3h2'),
  ], accents: [
    'm14 17 1 1 3-3',
  ]);
  static const rank = BrandIconData('rank', paths: [
    BrandPath('M4 20h16M5 17v-5h4v5m1 0V8h4v9m1 0v-6h4v6'),
  ], accents: [
    'm10 4 2-2 2 2',
  ]);
  static const library = BrandIconData('library', paths: [
    BrandPath('M7 3h10M5 6h14'),
    BrandPath('M7 9h10q4 0 4 4v4q0 4-4 4H7q-4 0-4-4v-4q0-4 4-4Z'),
  ], accents: [
    'm10 12 5 3-5 3z',
  ]);
  static const bookmark = BrandIconData('bookmark', paths: [
    BrandPath('M6 5q0-2 2-2h8q2 0 2 2v16l-6-4-6 4z'),
  ], accents: [
    'M10 7h4m-4 3h2',
  ]);
  static const heart = BrandIconData('heart', paths: [
    BrandPath('M12 20S3 15 3 8a5 5 0 0 1 9-3 5 5 0 0 1 9 3c0 7-9 12-9 12Z'),
  ], accents: [
    'M16 6q2 0 2 2',
  ]);
  static const star = BrandIconData('star', paths: [
    BrandPath('m12 3 3 6 6 1-4.5 4.5 1 6.5-5.5-3-5.5 3 1-6.5L3 10l6-1Z'),
  ], accents: [
    'm19 3 1-1m1 4h1',
  ]);
  static const bell = BrandIconData('bell', paths: [
    BrandPath('M8 18h8M9 21h6M5 17c2-2 1-4 1-7a6 6 0 0 1 12 0c0 3-1 5 1 7Z'),
  ], accents: [
    'm19 3 2 2',
  ]);
  static const user = BrandIconData('user', paths: [
    BrandPath('M16 8a4 4 0 1 1-8 0a4 4 0 0 1 8 0Z'),
    BrandPath('M4 21v-2c0-7 16-7 16 0v2M10 8h.1m3.9 0h.1'),
  ], accents: [
    'M19 6h2m-1-1v2',
  ]);
  static const history = BrandIconData('history', paths: [
    BrandPath('M4 8a9 9 0 1 1-1 7M3 3v5h5M12 7v5l3 2'),
  ], accents: [
    'M4 18h3',
  ]);
  static const logout = BrandIconData('logout', paths: [
    BrandPath('M10 3H6q-2 0-2 2v14q0 2 2 2h4M10 12h11m-4-4 4 4-4 4'),
  ], accents: [
    'M8 7h2',
  ]);
  static const play = BrandIconData('play', paths: [
    BrandPath('M8 4q-2-1-2 2v12q0 3 2 2l12-7q2-1 0-2Z'),
  ], accents: [
    'M2 8h1m-2 4h2m-1 4h1',
  ]);
  static const pause = BrandIconData('pause', paths: [
    BrandPath('M9 6v12q0 2-2 2t-2-2V6q0-2 2-2t2 2Z'),
    BrandPath('M19 6v12q0 2-2 2t-2-2V6q0-2 2-2t2 2Z'),
  ], accents: [
    'M11 12h2',
  ]);
  static const prev = BrandIconData('prev', paths: [
    BrandPath('m18 5-9 7 9 7ZM5 5v14'),
  ], accents: [
    'M3 9v6',
  ]);
  static const next = BrandIconData('next', paths: [
    BrandPath('m6 5 9 7-9 7ZM19 5v14'),
  ], accents: [
    'M21 9v6',
  ]);
  static const arrowLeft = BrandIconData('arrow-left', paths: [
    BrandPath('M20 12H4m6-6-6 6 6 6'),
  ], accents: [
    'M17 8h3',
  ]);
  static const arrowRight = BrandIconData('arrow-right', paths: [
    BrandPath('M4 12h16m-6-6 6 6-6 6'),
  ], accents: [
    'M4 16h3',
  ]);
  static const chevronDown = BrandIconData('chevron-down', paths: [
    BrandPath('m5 9 7 7 7-7'),
  ], accents: [
    'M11 5h2',
  ]);
  static const check = BrandIconData('check', paths: [
    BrandPath('m5 12 5 5L20 6'),
  ], accents: [
    'M3 17h3',
  ]);
  static const plus = BrandIconData('plus', paths: [
    BrandPath('M12 5v14M5 12h14'),
  ], accents: [
    'M18 4h2',
  ]);
  static const close = BrandIconData('close', paths: [
    BrandPath('m6 6 12 12M6 18 18 6'),
  ], accents: [
    'M20 3h1',
  ]);
  static const shuffle = BrandIconData('shuffle', paths: [
    BrandPath(
        'M3 6h3c4 0 8 12 12 12h3m-4-4 4 4-4 3M3 18h3c1 0 3-2 4-4m4-4c1-2 3-4 4-4h3m-4-3 4 3-4 4'),
  ], accents: [
    'M3 11h2',
  ]);
  static const sparkles = BrandIconData('sparkles', paths: [
    BrandPath('m10 4 2 6 6 2-6 2-2 6-2-6-6-2 6-2Z'),
  ], accents: [
    'm19 2 1 3 3 1-3 1-1 3-1-3-3-1 3-1Z',
  ]);
  static const smile = BrandIconData('smile', paths: [
    BrandPath('M6 8.5v7q0 4.5 6 4.5t6-4.5v-7q0-4.5-6-4.5t-6 4.5Z'),
    BrandPath('M8 10v1m8-1v1m-8 4q4 4 8 0'),
  ], accents: [
    'M18 3h3',
  ]);
  static const compass = BrandIconData('compass', paths: [
    BrandPath('M21 12a9 9 0 1 1-18 0a9 9 0 0 1 18 0Z'),
    BrandPath('m16 8-2 6-6 2 2-6Z'),
  ], accents: [
    'M12 2v2',
  ]);
  static const moon = BrandIconData('moon', paths: [
    BrandPath('M20 14A9 9 0 0 1 10 3a9 9 0 1 0 10 11Z'),
  ], accents: [
    'm18 3 1 2 2 1-2 1-1 2-1-2-2-1 2-1Z',
  ]);
  static const ratio = BrandIconData('ratio', paths: [
    BrandPath('M7 5h10q4 0 4 4v6q0 4-4 4H7q-4 0-4-4V9q0-4 4-4Z'),
    BrandPath('M7 9h4m-4 0v4m10 2h-4m4 0v-4'),
  ], accents: [
    'M11 2h2',
  ]);
  static const routes = BrandIconData('routes', paths: [
    BrandPath('M3 7h17m-4-4 4 4-4 4M21 17H4m4-4-4 4 4 4'),
  ], accents: [
    'M3 3h2m14 18h2',
  ]);
  static const episodes = BrandIconData('episodes', paths: [
    BrandPath('M10 6v3q0 2-2 2H5q-2 0-2-2V6q0-2 2-2h3q2 0 2 2Z'),
    BrandPath('M21 6v3q0 2-2 2h-3q-2 0-2-2V6q0-2 2-2h3q2 0 2 2Z'),
    BrandPath('M10 17v2q0 2-2 2H5q-2 0-2-2v-2q0-2 2-2h3q2 0 2 2Z'),
  ], accents: [
    'M14 16h7m-7 4h4',
  ]);
  static const repeat = BrandIconData('repeat', paths: [
    BrandPath(
        'M4 10V8q0-3 3-3h13m-3-3 3 3-3 3M20 14v2q0 3-3 3H4m3-3-3 3 3 3'),
  ], accents: [
    'm10 10 5 2-5 2Z',
  ]);
  static const volume = BrandIconData('volume', paths: [
    BrandPath('M3 9h4l5-5v16l-5-5H3ZM16 8q4 4 0 8'),
  ], accents: [
    'M19 5q7 7 0 14',
  ]);
  static const muted = BrandIconData('muted', paths: [
    BrandPath('M3 9h4l5-5v16l-5-5H3ZM16 9l6 6m-6 0 6-6'),
  ], accents: [
    'M18 4h2',
  ]);
  static const fullscreen = BrandIconData('fullscreen', paths: [
    BrandPath(
        'M8 3H5q-2 0-2 2v3m13-5h3q2 0 2 2v3M3 16v3q0 2 2 2h3m8 0h3q2 0 2-2v-3'),
  ], accents: [
    'M10 12h4',
  ]);
  static const message = BrandIconData('message', paths: [
    BrandPath('M7 4h10q4 0 4 4v6q0 4-4 4h-6l-6 3v-4q-2-1-2-3V8q0-4 4-4Z'),
    BrandPath('M7 9h10M7 13h5'),
  ], accents: [
    'M15 13h2',
  ]);
  static const mail = BrandIconData('mail', paths: [
    BrandPath('M7 5h10q4 0 4 4v6q0 4-4 4H7q-4 0-4-4V9q0-4 4-4Z'),
    BrandPath('m4 7 8 6 8-6'),
  ], accents: [
    'M17 21h3',
  ]);
  static const link = BrandIconData('link', paths: [
    BrandPath(
        'm10 8 3-3a4 4 0 0 1 6 6l-3 3m-2 2-3 3a4 4 0 0 1-6-6l3-3m1 5 6-6'),
  ], accents: [
    'M3 4h2',
  ]);
  static const lock = BrandIconData('lock', paths: [
    BrandPath('M20 14v3q0 4-4 4H8q-4 0-4-4v-3q0-4 4-4h8q4 0 4 4Z'),
    BrandPath('M8 10V7a4 4 0 0 1 8 0v3M12 14v3'),
  ], accents: [
    'M18 3h2',
  ]);
  static const settings = BrandIconData('settings', paths: [
    BrandPath('M4 7h16M4 17h16'),
    BrandPath('M11 7V4q0-2-2-2t-2 2v3'),
    BrandPath('M18 14v-3q0-2 2-2t2 2v3'),
  ], accents: [
    'M19 3h2',
  ]);
  static const speed = BrandIconData('speed', paths: [
    BrandPath(
        'M4 18a9 9 0 1 1 16 0M7 9l1 1m4-5v2m5 2-1 1M6 17h12m-6-3 4-3'),
  ], accents: [
    'M2 12h2',
  ]);
  static const arrowUp = BrandIconData('arrow-up', paths: [
    BrandPath('M12 20V4m-6 6 6-6 6 6'),
  ], accents: [
    'M4 18v2',
  ]);

  // ---------------------------------------------------------------------------
  // 品牌库没有、按同一套几何语言扩展的图标
  // ---------------------------------------------------------------------------
  static const chevronLeft = BrandIconData('chevron-left', paths: [
    BrandPath('m15 5-7 7 7 7'),
  ], accents: [
    'M18 8h3',
  ]);
  static const chevronRight = BrandIconData('chevron-right', paths: [
    BrandPath('m9 5 7 7-7 7'),
  ], accents: [
    'M3 8h3',
  ]);
  static const chevronUp = BrandIconData('chevron-up', paths: [
    BrandPath('m5 15 7-7 7 7'),
  ], accents: [
    'M11 19h2',
  ]);
  static const refresh = BrandIconData('refresh', paths: [
    BrandPath('M20 12a8 8 0 1 1-3.1-6.3M20 4.5V9h-4.5'),
  ], accents: [
    'M4 17h2',
  ]);
  static const alert = BrandIconData('alert', paths: [
    BrandPath('M21 12a9 9 0 1 1-18 0a9 9 0 0 1 18 0Z'),
    BrandPath('M12 7.2v5.6m0 3.7h.1'),
  ], accents: [
    'M19 3h2',
  ]);
  static const download = BrandIconData('download', paths: [
    BrandPath('M12 4v10.5m-4.5-4.5 4.5 4.5 4.5-4.5M5 20h14'),
  ], accents: [
    'M18 4h2',
  ]);
  static const book = BrandIconData('book', paths: [
    BrandPath(
        'M12 6Q9.4 4 4.5 4 3.6 4 3 4.2v15.6q.6-.2 1.5-.2 4.9 0 7.5 2 2.6-2 7.5-2 .9 0 1.5.2V4.2Q20.4 4 19.5 4 14.6 4 12 6Zm0 0v15.6'),
  ], accents: [
    'M16.5 8v3.5',
  ]);
  static const trash = BrandIconData('trash', paths: [
    BrandPath('M4 7h16'),
    BrandPath('M9.5 4.5h5q.9 0 .9.9V7H8.6V5.4q0-.9.9-.9Z'),
    BrandPath('M6 7l.8 11.4q.1 1.1 1.2 1.1h8q1.1 0 1.2-1.1L18 7M10 11v5m4-5v5'),
  ], accents: [
    'M18 3.5h2',
  ]);
  static const fastForward = BrandIconData('fast-forward', paths: [
    BrandPath('m3.5 6 6.5 6-6.5 6Zm10.5 0 6.5 6-6.5 6Z'),
  ], accents: [
    'M20 3h2',
  ]);
  static const rewind = BrandIconData('rewind', paths: [
    BrandPath('m20.5 6-7 6 7 6Zm-10 0-7 6 7 6Z'),
  ], accents: [
    'M2 9v6',
  ]);
  static const medal = BrandIconData('medal', paths: [
    BrandPath('M17.5 9a5.5 5.5 0 1 1-11 0 5.5 5.5 0 0 1 11 0Z'),
    BrandPath('m9.6 13.9-2.1 6.4 4.5-2.5 4.5 2.5-2.1-6.4'),
  ], accents: [
    'M19 3h2',
  ]);
  static const trophy = BrandIconData('trophy', paths: [
    BrandPath('M8 4.5h8V10a4 4 0 0 1-8 0V4.5Z'),
    BrandPath('M8 6H5v1.5A3.5 3.5 0 0 0 8.5 11M16 6h3v1.5A3.5 3.5 0 0 1 15.5 11'),
    BrandPath('M12 14v3.5M8.5 21h7m-6-4h5q1 0 1 1.2V21'),
  ], accents: [
    'M19 2.5h2',
  ]);
  static const sidebar = BrandIconData('sidebar', paths: [
    BrandPath('M7 4h10q4 0 4 4v8q0 4-4 4H7q-4 0-4-4V8q0-4 4-4Z'),
    BrandPath('M15 4v16'),
  ], accents: [
    'M11 2h2',
  ]);
  static const send = BrandIconData('send', paths: [
    BrandPath('m3.5 10.5 17-7-7 17-2.5-7.5-7.5-2.5ZM20.5 3.5 11 13'),
  ], accents: [
    'M3 4h2',
  ]);
  static const playCircle = BrandIconData('play-circle', paths: [
    BrandPath('M21 12a9 9 0 1 1-18 0a9 9 0 0 1 18 0Z'),
    BrandPath('m10 8.3 5.6 3.7-5.6 3.7Z'),
  ], accents: [
    'M12 2v2',
  ]);
  static const share = BrandIconData('share', paths: [
    BrandPath('M12 3.5V15m-4-7.5 4-4 4 4'),
    BrandPath('M6.5 11Q4 11 4 13.5V18q0 2.5 2.5 2.5h11Q20 20.5 20 18v-4.5Q20 11 17.5 11'),
  ], accents: [
    'M17 3h2',
  ]);
  static const forum = BrandIconData('forum', paths: [
    BrandPath('M12 4H6.5Q2.5 4 2.5 8v2q0 4 4 4h2'),
    BrandPath(
        'M11 8.5h6q4.5 0 4.5 4t-4.5 4h-1v3l-3.5-3H11q-4.5 0-4.5-4t4.5-4Z'),
  ], accents: [
    'M20 3h1',
  ]);
  static const edit = BrandIconData('edit', paths: [
    BrandPath('M4.5 19.5h4L19 9q1.6-1.6 0-3.2l-.8-.8Q16.6 3.4 15 5L4.5 15.5v4Zm10.5-13 3 3'),
  ], accents: [
    'M20 3h1',
  ]);
  static const checkCircle = BrandIconData('check-circle', paths: [
    BrandPath('M21 12a9 9 0 1 1-18 0a9 9 0 0 1 18 0Z'),
    BrandPath('m8 12.3 2.6 2.7 5.4-5.8'),
  ], accents: [
    'M3 4h2',
  ]);
  static const cancel = BrandIconData('cancel', paths: [
    BrandPath('M21 12a9 9 0 1 1-18 0a9 9 0 0 1 18 0Z'),
    BrandPath('m9 9 6 6m0-6-6 6'),
  ], accents: [
    'M18 3h2',
  ]);
  static const news = BrandIconData('news', paths: [
    BrandPath('M21 8v8q0 4-4 4H8q-4 0-4-4V8q0-4 4-4h9q4 0 4 4Z'),
    BrandPath('M8.5 9h8M8.5 12.5h8M8.5 16h4.5'),
  ], accents: [
    'M2 8h1m-2 4h2m-1 4h1',
  ]);
  static const notes = BrandIconData('notes', paths: [
    BrandPath('M4 6h13M4 11h16M4 16h9'),
  ], accents: [
    'M19 4h2',
  ]);
  static const arrowDown = BrandIconData('arrow-down', paths: [
    BrandPath('M12 4v16m-6-6 6 6 6-6'),
  ], accents: [
    'M4 4v2',
  ]);
  static const arrowUpRight = BrandIconData('arrow-up-right', paths: [
    BrandPath('M6.5 17.5 17.5 6.5M8.5 6.5h9v9'),
  ], accents: [
    'M4 18v2',
  ]);
  static const thumbUp = BrandIconData('thumb-up', paths: [
    BrandPath(
        'M8 10.5H5Q3.5 10.5 3.5 12v7q0 1.5 1.5 1.5h3Zm0 0 3.9-6.7q2.3 0 1.9 3.3l-.7 4.4h5.4q2.1 0 1.7 1.9l-1 5.4q-.3 1.7-2.1 1.7H7.5'),
  ], accents: [
    'M20 3h1',
  ]);
  static const subtitles = BrandIconData('subtitles', paths: [
    BrandPath('M21 9v6q0 4-4 4H7q-4 0-4-4V9q0-4 4-4h10q4 0 4 4Z'),
    BrandPath('M7.5 15h3m3 0h3.5'),
  ], accents: [
    'M11 2h2',
  ]);
  static const gamepad = BrandIconData('gamepad', paths: [
    BrandPath(
        'M7 7h10q2.2 0 3.3 1.7T21.6 14l-.5 2.8q-.4 2.2-2.5 2.2-1.5 0-2.4-1.1L15 16.6q-.7-.6-1.6-.6h-2.8q-.9 0-1.6.6l-1.2 1.3q-.9 1.1-2.4 1.1-2.1 0-2.5-2.2L2.4 14Q2 10.4 3.7 8.7T7 7Z'),
    BrandPath('M6.5 10.5v2.5m-1.25-1.25h2.5M15 12h.1m2.5-2h.1'),
  ], accents: [
    'M19 3h2',
  ]);
  static const tag = BrandIconData('tag', paths: [
    BrandPath(
        'M11.2 3H5Q3 3 3 5v6.2q0 1 .7 1.7l7.9 7.9q1.7 1.7 3.4 0l5.8-5.8q1.7-1.7 0-3.4l-7.9-7.9Q12.2 3 11.2 3ZM7.7 7.7h.1'),
  ], accents: [
    'm19 3 2 2',
  ]);
  static const rocket = BrandIconData('rocket', paths: [
    BrandPath('M12 2.5q4.8 2.4 4.8 9l-1.8 3H9l-1.8-3q0-6.6 4.8-9Z'),
    BrandPath('M9 14.5 6.5 16v3.5L9.5 18M15 14.5l2.5 1.5v3.5L14.5 18'),
    BrandPath('M13.2 8.3a1.7 1.7 0 1 1-2.4-2.4 1.7 1.7 0 0 1 2.4 2.4Z'),
  ], accents: [
    'M12 17.5v3.5',
  ]);
  static const flame = BrandIconData('flame', paths: [
    BrandPath(
        'M12 3q1 2.6 3.1 4.7 2 2 2.4 4.8a5.75 5.75 0 0 1-11 0Q7 9.7 8.9 7.7 11 5.6 12 3Z'),
  ], accents: [
    'M12 12.2q-1.9 1.6-1.9 3.4a1.9 1.9 0 0 0 3.8 0q0-1.8-1.9-3.4Z',
  ]);
  static const minus = BrandIconData('minus', paths: [
    BrandPath('M5 12h14'),
  ], accents: [
    'M18 4h2',
  ]);
  static const square = BrandIconData('square', paths: [
    BrandPath('M5 7q0-2 2-2h10q2 0 2 2v10q0 2-2 2H7q-2 0-2-2V7Z'),
  ], accents: [
    'M3 3h1',
  ]);
  static const restore = BrandIconData('restore', paths: [
    BrandPath('M20.5 11v7q0 2.5-2.5 2.5H11Q8.5 20.5 8.5 18v-7Q8.5 8.5 11 8.5h7q2.5 0 2.5 2.5Z'),
    BrandPath('M15.5 8.5V6.5q0-2.5-2.5-2.5h-7Q3.5 4 3.5 6.5v7Q3.5 16 6 16h2'),
  ], accents: [
    'M3 3h1',
  ]);
  static const sun = BrandIconData('sun', paths: [
    BrandPath('M16.5 12a4.5 4.5 0 1 1-9 0 4.5 4.5 0 0 1 9 0Z'),
    BrandPath('M12 20.5v-2M5.5 12h-2M20.5 12h-2M7.3 7.3 5.9 5.9M18.1 18.1l-1.4-1.4M16.7 7.3l1.4-1.4M5.9 18.1l1.4-1.4'),
  ], accents: [
    'M12 5.5V3.5',
  ]);
  static const keyboard = BrandIconData('keyboard', paths: [
    BrandPath('M21.5 9.5v5q0 3.5-3.5 3.5H6Q2.5 18 2.5 14.5v-5Q2.5 6 6 6h12q3.5 0 3.5 3.5Z'),
    BrandPath('M7 10h.1M12 10h.1M17 10h.1M7 14h.1M9.5 14h5M17 14h.1'),
  ], accents: [
    'M11 3h2',
  ]);
  static const image = BrandIconData('image', paths: [
    BrandPath('M7 5h10q4 0 4 4v6q0 4-4 4H7q-4 0-4-4V9q0-4 4-4Z'),
    BrandPath('M6.5 15.5l3.4-4q.6-.7 1.2 0l2.4 2.9m1.4-1.4 1-1.1q.6-.7 1.2 0l1.6 1.9M9.2 9.2h.1'),
  ], accents: [
    'M11 2h2',
  ]);
  static const quote = BrandIconData('quote', paths: [
    BrandPath('M10.5 7.5H7q-2 0-2 2V12q0 2 2 2h1.5q0 3-3.5 4'),
    BrandPath('M19 7.5h-3.5q-2 0-2 2V12q0 2 2 2H17q0 3-3.5 4'),
  ], accents: [
    'M19 3h2',
  ]);
  static const flag = BrandIconData('flag', paths: [
    BrandPath('M5.5 21V4'),
    BrandPath('M5.5 5.2q3.5-2.2 7 0t7 0V14q-3.5 2.2-7 0t-7 0'),
  ], accents: [
    'M19 2.5h2',
  ]);
  static const fit = BrandIconData('fit', paths: [
    BrandPath('M9 4H7Q3 4 3 8v1M15 4h2q4 0 4 4v1M9 20H7q-4 0-4-4v-1M15 20h2q4 0 4-4v-1'),
    BrandPath('M10.5 12h3'),
  ], accents: [
    'M11 1.5h2',
  ]);
  static const hanger = BrandIconData('hanger', paths: [
    BrandPath(
        'M12 6.5a2 2 0 1 0-2-2m2 2v1L20.5 13q1.5 1 .75 2.25T18.75 16.5H5.25Q4.5 16.5 3.75 15.25T4.5 13L12 7.5'),
  ], accents: [
    'M19 3h2',
  ]);
  static const ban = BrandIconData('ban', paths: [
    BrandPath('M21 12a9 9 0 1 1-18 0a9 9 0 0 1 18 0Z'),
    BrandPath('M5.6 5.6l12.8 12.8'),
  ], accents: [
    'M20 18h1',
  ]);
  static const badge = BrandIconData('badge', paths: [
    BrandPath('M7 5h10q4 0 4 4v6q0 4-4 4H7q-4 0-4-4V9q0-4 4-4Z'),
    BrandPath('M8.6 13.6a2.1 2.1 0 1 0-.01-4.2 2.1 2.1 0 0 0 .01 4.2Zm-3.1 2.9q.7-1.9 3.1-1.9t3.1 1.9'),
    BrandPath('M15 9.5h3m-3 3.5h3'),
  ], accents: [
    'M11 2h2',
  ]);
  static const volumeLow = BrandIconData('volume-low', paths: [
    BrandPath('M3 9h4l5-5v16l-5-5H3Z'),
    BrandPath('M15.5 10q1.8 2 0 4'),
  ], accents: [
    'M19 4h2',
  ]);
  static const login = BrandIconData('login', paths: [
    BrandPath('M13 3H7Q5 3 5 5v14q0 2 2 2h6M21 12H10.5m4-4-4 4 4 4'),
  ], accents: [
    'M8 7h2',
  ]);
  static const live = BrandIconData('live', paths: [
    BrandPath('M21 11v6q0 3.5-3.5 3.5h-11Q3 20.5 3 17v-6q0-3.5 3.5-3.5h11q3.5 0 3.5 3.5Z'),
    BrandPath('m8.5 3 3.5 3.5L15.5 3'),
    BrandPath('m10.3 11.2 4 2.3-4 2.3Z'),
  ], accents: [
    'M19 3h2',
  ]);
  static const grid = BrandIconData('grid', paths: [
    BrandPath('M10.5 6.5v2q0 2-2 2h-2q-2 0-2-2v-2q0-2 2-2h2q2 0 2 2Z'),
    BrandPath('M19.5 6.5v2q0 2-2 2h-2q-2 0-2-2v-2q0-2 2-2h2q2 0 2 2Z'),
    BrandPath('M10.5 15.5v2q0 2-2 2h-2q-2 0-2-2v-2q0-2 2-2h2q2 0 2 2Z'),
    BrandPath('M19.5 15.5v2q0 2-2 2h-2q-2 0-2-2v-2q0-2 2-2h2q2 0 2 2Z'),
  ], accents: [
    'M11 1.5h2',
  ]);
  static const playlist = BrandIconData('playlist', paths: [
    BrandPath('M4.5 6h13M4.5 11h13M4.5 16h6.5'),
    BrandPath('m14.5 12.8 5.5 3.2-5.5 3.2Z'),
  ], accents: [
    'M19 3.5h2',
  ]);
  static const title = BrandIconData('title', paths: [
    BrandPath('M5.5 5.5h13M12 5.5V19M9.5 19h5'),
  ], accents: [
    'M19 3h2',
  ]);
  static const unlock = BrandIconData('unlock', paths: [
    BrandPath('M20 14v3q0 4-4 4H8q-4 0-4-4v-3q0-4 4-4h8q4 0 4 4Z'),
    BrandPath('M8 10V7a4 4 0 0 1 7.8-1.3M12 14v3'),
  ], accents: [
    'M18 3h2',
  ]);
  static const fullscreenExit = BrandIconData('fullscreen-exit', paths: [
    BrandPath(
        'M8.5 3v3.5Q8.5 8 7 8H3.5M15.5 3v3.5Q15.5 8 17 8h3.5M8.5 21v-3.5Q8.5 16 7 16H3.5M15.5 21v-3.5Q15.5 16 17 16h3.5'),
  ], accents: [
    'M10 12h4',
  ]);
}

// -----------------------------------------------------------------------------
// 渲染
// -----------------------------------------------------------------------------

/// bllii 品牌图标。对外接口对齐 [Icon]：`BrandIcon(BIcons.play, size: 20)`。
class BrandIcon extends StatelessWidget {
  final BrandIconData data;
  final double? size;
  final Color? color;

  /// 完全不绘制粉色点缀（速度短线）。
  /// 导航、系统 chrome、大尺寸主行动按钮用单色纯形，避免点缀被误读成角标。
  final bool monochrome;

  /// 实心填充（心形 / 星标 / 消息气泡等的「已激活」态）。
  final bool filled;

  final String? semanticLabel;

  const BrandIcon(
    this.data, {
    super.key,
    this.size,
    this.color,
    this.monochrome = false,
    this.filled = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconTheme = IconTheme.of(context);
    final effectiveColor = color ??
        iconTheme.color ??
        theme.iconTheme.color ??
        (theme.brightness == Brightness.dark
            ? AppIconInk.dark
            : AppIconInk.light);
    final effectiveSize = size ?? iconTheme.size ?? 24.0;

    final icon = SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: CustomPaint(
        painter: _BrandIconPainter(
          data: data,
          color: effectiveColor,
          monochrome: monochrome,
          filled: filled,
        ),
      ),
    );

    if (semanticLabel == null) return icon;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(child: icon),
    );
  }
}

/// IconTheme 缺色时的兜底墨色，与品牌正文色一致。
abstract final class AppIconInk {
  static const light = Color(0xFF353B58);
  static const dark = Color(0xFFE6EAF5);
}

class _BrandIconPainter extends CustomPainter {
  final BrandIconData data;
  final Color color;
  final bool monochrome;
  final bool filled;

  const _BrandIconPainter({
    required this.data,
    required this.color,
    required this.monochrome,
    required this.filled,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    for (final path in data.paths) {
      final p = _pathOf(path.d);
      if (filled) {
        canvas.drawPath(p, Paint()..color = color);
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = path.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = path.color ?? color,
      );
    }
    // 单色模式直接跳过点缀笔画（速度短线）
    if (!monochrome) {
      for (final d in data.accents) {
        final p = _pathOf(d);
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = kBrandIconAccent,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandIconPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.color != color ||
      oldDelegate.monochrome != monochrome ||
      oldDelegate.filled != filled;
}

// -----------------------------------------------------------------------------
// 迷你 SVG path 解析器（M/L/H/V/C/S/Q/T/A/Z 及其相对命令，含隐式重复）
// -----------------------------------------------------------------------------

final Map<String, ui.Path> _pathCache = {};

ui.Path _pathOf(String d) => _pathCache.putIfAbsent(d, () => _parsePath(d));

ui.Path _parsePath(String d) {
  final path = ui.Path();
  final scanner = _PathScanner(d);
  double x = 0, y = 0;
  double cx = 0, cy = 0; // 上一个 cubic/quadratic 控制点（S/T 用）
  var startX = 0.0, startY = 0.0;
  String? lastCmd;
  var lastCurve = ''; // 'c' / 'q'，用于 S/T 的控制点反射判定

  while (!scanner.done) {
    scanner.skipSeparators();
    if (scanner.done) break;
    final ch = scanner.peek();
    final isCommand = _commandLetters.contains(ch);
    String cmd;
    if (isCommand) {
      cmd = ch;
      scanner.advance();
      lastCmd = cmd;
    } else {
      // 隐式重复：M 之后的重复段按 L/m 处理
      if (lastCmd == null) break;
      cmd = (lastCmd == 'M') ? 'L' : (lastCmd == 'm') ? 'l' : lastCmd;
    }
    if (cmd != 'C' && cmd != 'c' && cmd != 'S' && cmd != 's' && cmd != 'Q' &&
        cmd != 'q' && cmd != 'T' && cmd != 't') {
      lastCurve = '';
    }

    switch (cmd) {
      case 'M':
      case 'm':
        // SVG 规范：M/m 之后的隐式重复坐标按 L/l（直线）处理
        var firstMove = true;
        do {
          final px = scanner.number();
          final py = scanner.number();
          if (cmd == 'm') {
            x += px;
            y += py;
          } else {
            x = px;
            y = py;
          }
          if (firstMove) {
            path.moveTo(x, y);
            startX = x;
            startY = y;
            firstMove = false;
          } else {
            path.lineTo(x, y);
          }
        } while (scanner.hasMoreNumbers());
        break;
      case 'L':
      case 'l':
        do {
          final px = scanner.number();
          final py = scanner.number();
          if (cmd == 'l') {
            x += px;
            y += py;
          } else {
            x = px;
            y = py;
          }
          path.lineTo(x, y);
        } while (scanner.hasMoreNumbers());
        break;
      case 'H':
      case 'h':
        do {
          final px = scanner.number();
          if (cmd == 'h') {
            x += px;
          } else {
            x = px;
          }
          path.lineTo(x, y);
        } while (scanner.hasMoreNumbers());
        break;
      case 'V':
      case 'v':
        do {
          final py = scanner.number();
          if (cmd == 'v') {
            y += py;
          } else {
            y = py;
          }
          path.lineTo(x, y);
        } while (scanner.hasMoreNumbers());
        break;
      case 'C':
      case 'c':
        do {
          final x1 = scanner.number();
          final y1 = scanner.number();
          final x2 = scanner.number();
          final y2 = scanner.number();
          final px = scanner.number();
          final py = scanner.number();
          if (cmd == 'c') {
            path.cubicTo(x + x1, y + y1, x + x2, y + y2, x + px, y + py);
            cx = x + x2;
            cy = y + y2;
            x += px;
            y += py;
          } else {
            path.cubicTo(x1, y1, x2, y2, px, py);
            cx = x2;
            cy = y2;
            x = px;
            y = py;
          }
        } while (scanner.hasMoreNumbers());
        break;
      case 'S':
      case 's':
        do {
          final x2 = scanner.number();
          final y2 = scanner.number();
          final px = scanner.number();
          final py = scanner.number();
          // 反射上一个控制点；上一命令不是曲线时反射点就是当前点
          final rx = lastCurve == 'c' ? 2 * x - cx : x;
          final ry = lastCurve == 'c' ? 2 * y - cy : y;
          if (cmd == 's') {
            path.cubicTo(rx, ry, x + x2, y + y2, x + px, y + py);
            cx = x + x2;
            cy = y + y2;
            x += px;
            y += py;
          } else {
            path.cubicTo(rx, ry, x2, y2, px, py);
            cx = x2;
            cy = y2;
            x = px;
            y = py;
          }
          lastCurve = 'c';
        } while (scanner.hasMoreNumbers());
        break;
      case 'Q':
      case 'q':
        do {
          final x1 = scanner.number();
          final y1 = scanner.number();
          final px = scanner.number();
          final py = scanner.number();
          if (cmd == 'q') {
            path.quadraticBezierTo(x + x1, y + y1, x + px, y + py);
            cx = x + x1;
            cy = y + y1;
            x += px;
            y += py;
          } else {
            path.quadraticBezierTo(x1, y1, px, py);
            cx = x1;
            cy = y1;
            x = px;
            y = py;
          }
        } while (scanner.hasMoreNumbers());
        break;
      case 'T':
      case 't':
        do {
          final px = scanner.number();
          final py = scanner.number();
          final rx = lastCurve == 'q' ? 2 * x - cx : x;
          final ry = lastCurve == 'q' ? 2 * y - cy : y;
          if (cmd == 't') {
            path.quadraticBezierTo(rx, ry, x + px, y + py);
            x += px;
            y += py;
          } else {
            path.quadraticBezierTo(rx, ry, px, py);
            x = px;
            y = py;
          }
          cx = rx;
          cy = ry;
          lastCurve = 'q';
        } while (scanner.hasMoreNumbers());
        break;
      case 'A':
      case 'a':
        do {
          final rx = scanner.number();
          final ry = scanner.number();
          final rotation = scanner.number();
          final largeArc = scanner.number() != 0;
          final sweep = scanner.number() != 0;
          final px = scanner.number();
          final py = scanner.number();
          final ex = cmd == 'a' ? x + px : px;
          final ey = cmd == 'a' ? y + py : py;
          _addArc(path, x, y, ex, ey, rx.abs(), ry.abs(), rotation, largeArc,
              sweep);
          x = ex;
          y = ey;
        } while (scanner.hasMoreNumbers());
        break;
      case 'Z':
      case 'z':
        path.close();
        x = startX;
        y = startY;
        break;
      default:
        // 未知命令：跳过，避免死循环
        scanner.advance();
    }
  }
  return path;
}

const String _commandLetters = 'MmLlHhVvCcSsQqTtAaZz';

class _PathScanner {
  final String s;
  int i = 0;
  _PathScanner(this.s);

  bool get done => i >= s.length;

  String peek() => s[i];

  void advance() => i++;

  void skipSeparators() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C) {
        i++;
      } else {
        break;
      }
    }
  }

  bool _atNumberStart() {
    if (i >= s.length) return false;
    final c = s[i];
    if (_isDigit(c) || c == '.') return true;
    if ((c == '-' || c == '+') && i + 1 < s.length) {
      final n = s[i + 1];
      return _isDigit(n) || n == '.';
    }
    return false;
  }

  bool hasMoreNumbers() {
    skipSeparators();
    return _atNumberStart();
  }

  double number() {
    skipSeparators();
    final start = i;
    var seenDot = false;
    while (i < s.length) {
      final c = s[i];
      if (_isDigit(c)) {
        i++;
      } else if (c == '.') {
        if (seenDot) break; // "1.5.5" → 第二个点开启新数字
        seenDot = true;
        i++;
      } else if (c == '-' || c == '+') {
        if (i == start) {
          i++;
        } else {
          break; // 符号意味着新数字开始
        }
      } else if ((c == 'e' || c == 'E') && i + 1 < s.length) {
        final n = s[i + 1];
        if (_isDigit(n) || n == '-' || n == '+') {
          i += 2;
        } else {
          break;
        }
      } else {
        break;
      }
    }
    final text = s.substring(start, i);
    return double.tryParse(text) ?? 0;
  }

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}

/// SVG 椭圆弧 → 三次贝塞尔（W3C 规范 F.6 端点参数化转中心参数化）。
void _addArc(
  ui.Path path,
  double x1,
  double y1,
  double x2,
  double y2,
  double rx,
  double ry,
  double rotationDeg,
  bool largeArc,
  bool sweep,
) {
  if (x1 == x2 && y1 == y2) return;
  final phi = rotationDeg * math.pi / 180;
  final cosP = math.cos(phi);
  final sinP = math.sin(phi);

  final dx2 = (x1 - x2) / 2;
  final dy2 = (y1 - y2) / 2;
  final x1p = cosP * dx2 + sinP * dy2;
  final y1p = -sinP * dx2 + cosP * dy2;

  var rxs = rx * rx;
  var rys = ry * ry;
  final lambda = x1p * x1p / rxs + y1p * y1p / rys;
  if (lambda > 1) {
    final s = math.sqrt(lambda);
    rx *= s;
    ry *= s;
    rxs = rx * rx;
    rys = ry * ry;
  }

  final sign = (largeArc != sweep) ? 1.0 : -1.0;
  var factor = (rxs * rys - rxs * y1p * y1p - rys * x1p * x1p) /
      (rxs * y1p * y1p + rys * x1p * x1p);
  if (factor < 0) factor = 0;
  final coef = sign * math.sqrt(factor);
  final cxp = coef * rx * y1p / ry;
  final cyp = -coef * ry * x1p / rx;
  final cx = cosP * cxp - sinP * cyp + (x1 + x2) / 2;
  final cy = sinP * cxp + cosP * cyp + (y1 + y2) / 2;

  double angleOf(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final len = math.sqrt(ux * ux + uy * uy) * math.sqrt(vx * vx + vy * vy);
    var ang = math.acos((dot / len).clamp(-1.0, 1.0));
    if (ux * vy - uy * vx < 0) ang = -ang;
    return ang;
  }

  final theta1 = angleOf(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  var delta = angleOf((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx,
      (-y1p - cyp) / ry);
  if (!sweep && delta > 0) {
    delta -= 2 * math.pi;
  } else if (sweep && delta < 0) {
    delta += 2 * math.pi;
  }

  final segments = (delta.abs() / (math.pi / 2)).ceil().clamp(1, 4);
  final step = delta / segments;
  final t = 4 / 3 * math.tan(step / 4);

  ui.Offset point(double cosT, double sinT) => ui.Offset(
        cosP * rx * cosT - sinP * ry * sinT + cx,
        sinP * rx * cosT + cosP * ry * sinT + cy,
      );

  ui.Offset derivative(double cosT, double sinT) => ui.Offset(
        -cosP * rx * sinT - sinP * ry * cosT,
        -sinP * rx * cosT + cosP * ry * cosT,
      );

  var theta = theta1;
  for (var i = 0; i < segments; i++) {
    final next = theta + step;
    final cos1 = math.cos(theta);
    final sin1 = math.sin(theta);
    final cos2 = math.cos(next);
    final sin2 = math.sin(next);
    final p1 = point(cos1, sin1);
    final p2 = point(cos2, sin2);
    final d1 = derivative(cos1, sin1) * t;
    final d2 = derivative(cos2, sin2) * t;
    path.cubicTo(
      p1.dx + d1.dx,
      p1.dy + d1.dy,
      p2.dx - d2.dx,
      p2.dy - d2.dy,
      p2.dx,
      p2.dy,
    );
    theta = next;
  }
}
