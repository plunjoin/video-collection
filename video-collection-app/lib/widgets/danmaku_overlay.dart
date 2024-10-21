import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const danmakuPalette = <String>[
  '#FFFFFF',
  '#FFE14D',
  '#FF6B9A',
  '#7CFFB2',
  '#7AD7FF',
  '#C9A6FF',
  '#FF9F43',
];

class DanmakuItem {
  final int id;
  final int playTimeMs;
  final int mode;
  final String color;
  final String content;
  final int userId;
  final String authorName;

  const DanmakuItem({
    required this.id,
    required this.playTimeMs,
    required this.mode,
    required this.color,
    required this.content,
    required this.userId,
    required this.authorName,
  });

  factory DanmakuItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    return DanmakuItem(
      id: asInt(json['id']),
      playTimeMs: asInt(json['play_time_ms']),
      mode: asInt(json['mode']).clamp(0, 2).toInt(),
      color: json['color']?.toString().isNotEmpty == true
          ? json['color'].toString()
          : '#FFFFFF',
      content: json['content']?.toString() ?? '',
      userId: asInt(json['user_id']),
      authorName: json['author_name']?.toString() ?? '',
    );
  }
}

class _Shot {
  _Shot({
    required this.item,
    required this.lane,
    required this.textWidth,
  });

  final DanmakuItem item;
  final int lane;
  final double textWidth;
  double progress = 0;
}

/// 按播放时间把弹幕铺到画面上。滚动、顶部和底部三种位置会各自避开重叠。
class DanmakuOverlay extends StatefulWidget {
  final List<DanmakuItem> items;
  final String episodeKey;
  final Duration position;
  final bool enabled;
  final bool playing;
  final double opacity;
  final double fontScale;
  final double speed;
  final double area;
  final List<String> blocked;

  const DanmakuOverlay({
    super.key,
    required this.items,
    required this.episodeKey,
    required this.position,
    required this.enabled,
    required this.playing,
    this.opacity = 1,
    this.fontScale = 1,
    this.speed = 1,
    this.area = 0.5,
    this.blocked = const [],
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  final List<_Shot> _shots = [];
  final Set<int> _seen = {};
  late final Ticker _ticker;
  Duration? _lastTick;
  int _cursorMs = 0;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _cursorMs = widget.position.inMilliseconds;
    _markPassed(_cursorMs);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodeKey != widget.episodeKey) {
      _shots.clear();
      _seen.clear();
      _cursorMs = widget.position.inMilliseconds;
      _markPassed(_cursorMs);
      _spawnRange(_cursorMs - 120, _cursorMs);
      return;
    }
    final previousIds = oldWidget.items.map((item) => item.id).toSet();
    final now = widget.position.inMilliseconds;
    for (final item in widget.items) {
      if (previousIds.contains(item.id)) continue;
      if (item.playTimeMs <= now && item.playTimeMs >= now - 3000) {
        _spawn(item);
      } else if (item.playTimeMs < now) {
        _seen.add(item.id);
      }
    }
    final live = widget.items.map((item) => item.id).toSet();
    _shots.removeWhere((shot) => !live.contains(shot.item.id));
    if (now + 800 < _cursorMs || now > _cursorMs + 1500) {
      _shots.clear();
      _seen.clear();
      _markPassed(now);
      _spawnRange(now - 120, now);
    } else if (now > _cursorMs) {
      _spawnRange(_cursorMs, now);
    }
    _cursorMs = now;
    if (!widget.enabled) _shots.clear();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (!mounted || !widget.enabled || !widget.playing || _shots.isEmpty) {
      return;
    }
    final seconds = previous == null
        ? 0.0
        : (elapsed - previous).inMicroseconds / 1000000;
    if (seconds <= 0) return;
    final speed = widget.speed.clamp(0.5, 2).toDouble();
    setState(() {
      _shots.removeWhere((shot) {
        final duration = shot.item.mode == 0 ? 8 / speed : 4;
        shot.progress += seconds / duration;
        return shot.progress >= 1;
      });
    });
  }

  void _markPassed(int ms) {
    for (final item in widget.items) {
      if (item.playTimeMs < ms - 120) _seen.add(item.id);
    }
  }

  void _spawnRange(int from, int to) {
    for (final item in widget.items) {
      if (item.playTimeMs > from && item.playTimeMs <= to) _spawn(item);
    }
  }

  bool _blocked(String content) {
    final text = content.toLowerCase();
    return widget.blocked.any(
      (word) => word.isNotEmpty && text.contains(word.toLowerCase()),
    );
  }

  void _spawn(DanmakuItem item) {
    if (!widget.enabled || _seen.contains(item.id) || item.content.isEmpty) {
      return;
    }
    if (_size.isEmpty) return;
    if (_blocked(item.content)) {
      _seen.add(item.id);
      return;
    }
    final textWidth = _measure(item).width;
    final lanes = _laneCount();
    int? lane;
    for (var index = 0; index < lanes; index++) {
      if (_laneFree(item.mode, index, textWidth)) {
        lane = index;
        break;
      }
    }
    _seen.add(item.id);
    if (lane == null || _shots.length >= 48) return;
    _shots.add(_Shot(item: item, lane: lane, textWidth: textWidth));
  }

  int _laneCount() {
    final row = 26.0 * widget.fontScale.clamp(0.8, 1.4);
    final band = _size.height * widget.area.clamp(0.25, 0.9);
    return (band / row).floor().clamp(1, 12);
  }

  bool _laneFree(int mode, int lane, double textWidth) {
    for (final shot in _shots) {
      if (shot.item.mode != mode || shot.lane != lane) continue;
      if (mode != 0) return false;
      final travel = _size.width + shot.textWidth;
      final right = _size.width - shot.progress * travel + shot.textWidth;
      if (right > _size.width - textWidth * 0.15 - 28) return false;
    }
    return true;
  }

  TextPainter _measure(DanmakuItem item) {
    return TextPainter(
      text: TextSpan(
        text: item.content,
        style: TextStyle(
          fontSize: 16 * widget.fontScale.clamp(0.8, 1.4),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 420);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.expand();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final next = Size(constraints.maxWidth, constraints.maxHeight);
          if (next != _size && next.width > 0 && next.height > 0) {
            final wasEmpty = _size.isEmpty;
            _size = next;
            if (wasEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _spawnRange(_cursorMs - 120, _cursorMs);
                setState(() {});
              });
            }
          }
          return CustomPaint(
            size: next,
            painter: _DanmakuPainter(
              shots: List<_Shot>.from(_shots),
              opacity: widget.opacity.clamp(0.2, 1).toDouble(),
              fontScale: widget.fontScale.clamp(0.8, 1.4).toDouble(),
              area: widget.area.clamp(0.25, 0.9).toDouble(),
            ),
          );
        },
      ),
    );
  }
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required this.shots,
    required this.opacity,
    required this.fontScale,
    required this.area,
  });

  final List<_Shot> shots;
  final double opacity;
  final double fontScale;
  final double area;

  @override
  void paint(Canvas canvas, Size size) {
    final row = 26.0 * fontScale;
    final bandBottom = math.max(row, size.height * area);
    for (final shot in shots) {
      final painter = TextPainter(
        text: TextSpan(
          text: shot.item.content,
          style: TextStyle(
            color: _color(shot.item.color).withValues(alpha: opacity),
            fontSize: 16 * fontScale,
            fontWeight: FontWeight.w800,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: opacity),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width * 0.72);
      final double y = shot.item.mode == 2
          ? (size.height - 36 - shot.lane * row)
                .clamp(8.0, math.max(8.0, size.height - 28))
                .toDouble()
          : (8 + shot.lane * row)
                .clamp(4.0, math.max(4.0, bandBottom - 8))
                .toDouble();
      final double x;
      if (shot.item.mode == 0) {
        x = size.width - shot.progress * (size.width + painter.width);
      } else {
        x = (size.width - painter.width) / 2;
      }
      painter.paint(canvas, Offset(x, y.toDouble()));
    }
  }

  Color _color(String value) {
    final hex = value.replaceFirst('#', '');
    if (hex.length != 6) return Colors.white;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return Colors.white;
    return Color(0xFF000000 | parsed);
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) => true;
}

Future<({String text, String color, int mode})?> showDanmakuComposer(
  BuildContext context, {
  String initial = '',
}) {
  return showModalBottomSheet<({String text, String color, int mode})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _DanmakuComposer(initial: initial),
  );
}

class _DanmakuComposer extends StatefulWidget {
  final String initial;
  const _DanmakuComposer({required this.initial});

  @override
  State<_DanmakuComposer> createState() => _DanmakuComposerState();
}

class _DanmakuComposerState extends State<_DanmakuComposer> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  String _color = danmakuPalette.first;
  int _mode = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    if (text.runes.length > 40) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('弹幕最多 40 个字')));
      return;
    }
    Navigator.of(context).pop((text: text, color: _color, mode: _mode));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '发送弹幕',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              hintText: '发一条应景的弹幕',
              prefixIcon: Icon(Icons.subtitles_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final mode in [(0, '滚动'), (1, '顶部'), (2, '底部')])
                ChoiceChip(
                  label: Text(mode.$2),
                  selected: _mode == mode.$1,
                  onSelected: (_) => setState(() => _mode = mode.$1),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final color in danmakuPalette)
                GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: _parse(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == color
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black26,
                        width: _color == color ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _submit, child: const Text('发送')),
          ),
        ],
      ),
    );
  }

  Color _parse(String value) {
    final parsed = int.tryParse(value.replaceFirst('#', ''), radix: 16);
    if (parsed == null) return Colors.white;
    return Color(0xFF000000 | parsed);
  }
}
