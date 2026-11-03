/// M3U8 切片广告规则。只处理点播，直播保留列表与刷新行为。
class M3u8CleanOptions {
  final bool enableFilter, filterHeadAd, filterMiddleAd;
  final double maxHeadAdDuration, maxMiddleAdDuration;
  final List<String> blacklistKeywords;

  const M3u8CleanOptions({
    this.enableFilter = true,
    this.filterHeadAd = true,
    this.filterMiddleAd = true,
    this.maxHeadAdDuration = 60,
    this.maxMiddleAdDuration = 90,
    this.blacklistKeywords = const [
      'guanggao',
      'ad.',
      '/ad/',
      '/ads/',
      'advert',
      'union',
      'adwords',
      'open.ad',
      'tg.mp4',
      'tg.ts',
      'banner',
    ],
  });
}

class _Segment {
  final String uri, key, map;
  final List<String> tags;
  final BigInt? seq;
  final bool ad;
  _Segment(this.uri, this.tags, this.key, this.map, this.seq, this.ad);
}

class _Group {
  final items = <_Segment>[];
  final bool boundary;
  double duration = 0;
  BigInt? min, max;
  _Group(this.boundary);

  void summarize() {
    final seqs = items.map((item) => item.seq).whereType<BigInt>().toList();
    if (seqs.isNotEmpty && seqs.length >= items.length / 2) {
      min = seqs.reduce((a, b) => a < b ? a : b);
      max = seqs.reduce((a, b) => a > b ? a : b);
    }
  }
}

class M3u8Cleaner {
  static final uriAttribute = RegExp(r'URI="([^"]+)"');
  static bool isMaster(String text) => RegExp(
    r'^#EXT-X-(?:STREAM-INF|I-FRAME-STREAM-INF):',
    multiLine: true,
  ).hasMatch(text);

  static String rewriteLine(String line, Uri origin) {
    if (line.isEmpty || line.startsWith('#')) {
      return line.replaceAllMapped(
        uriAttribute,
        (match) => 'URI="${origin.resolve(match[1]!)}"',
      );
    }
    return origin.resolve(line).toString();
  }

  static BigInt? segmentSequence(String uri) {
    final name = Uri.parse(uri).path.split('/').last;
    final match = RegExp(
      r'(?:^|[^0-9])([0-9]+)\.(?:ts|image|jpeg|jpg|png|webp|m4s|mp4)(?:$|[^a-z])',
      caseSensitive: false,
    ).firstMatch(name);
    return match == null ? null : BigInt.tryParse(match[1]!);
  }

  static String clean(
    String text,
    Uri origin, {
    M3u8CleanOptions options = const M3u8CleanOptions(),
  }) {
    final lines = text
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty || lines.first != '#EXTM3U') {
      throw const FormatException('Invalid M3U8 playlist');
    }
    if (isMaster(text) ||
        !lines.contains('#EXT-X-ENDLIST') ||
        lines.any(
          (line) =>
              RegExp(r'^#EXT-X-(?:PART|SKIP|PRELOAD-HINT):').hasMatch(line),
        )) {
      return lines.map((line) => rewriteLine(line, origin)).join('\n');
    }
    final header = <String>[], footer = <String>[], groups = <_Group>[];
    var group = _Group(false);
    var tags = <String>[];
    var duration = 0.0;
    var key = '', map = '', rangeUri = '';
    var sequence = BigInt.zero, segmentIndex = BigInt.zero;
    var rangeEnd = 0;
    for (final line in lines) {
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = BigInt.parse(line.split(':')[1].trim());
      }
    }
    for (final raw in lines) {
      final line = rewriteLine(raw, origin);
      if (line == '#EXT-X-DISCONTINUITY') {
        if (group.items.isNotEmpty) groups.add(group);
        group = _Group(true);
      } else if (line == '#EXT-X-ENDLIST') {
        footer.add(line);
      } else if (line.startsWith('#EXT-X-KEY:')) {
        key = line;
      } else if (line.startsWith('#EXT-X-MAP:')) {
        map = line;
      } else if (line.startsWith('#EXTINF:')) {
        duration = double.parse(line.substring(8).split(',')[0]);
        if (!duration.isFinite) throw const FormatException('Invalid duration');
        tags.add(line);
      } else if (line.startsWith('#')) {
        if (groups.isEmpty &&
            group.items.isEmpty &&
            tags.isEmpty &&
            !line.startsWith('#EXT-X-BYTERANGE:')) {
          header.add(line);
        } else {
          tags.add(line);
        }
      } else {
        // IV 与隐式 BYTERANGE 使用原始位置，避免删片后解密或偏移错误。
        var segmentKey = key;
        if (key.contains('METHOD=AES-128') &&
            !RegExp(r'[:,]IV=').hasMatch(key)) {
          final iv = (sequence + segmentIndex)
              .toRadixString(16)
              .padLeft(32, '0');
          segmentKey = '$key,IV=0x$iv';
        }
        tags = tags.map((tag) {
          if (!tag.startsWith('#EXT-X-BYTERANGE:')) return tag;
          final parts = tag.substring(17).split('@');
          final length = int.parse(parts[0]);
          final start = parts.length > 1
              ? int.parse(parts[1])
              : (rangeUri == line ? rangeEnd : 0);
          rangeEnd = start + length;
          rangeUri = line;
          return '#EXT-X-BYTERANGE:$length@$start';
        }).toList();
        final ad =
            options.enableFilter &&
            options.blacklistKeywords.any(
              (word) =>
                  word.isNotEmpty &&
                  line.toLowerCase().contains(word.toLowerCase()),
            );
        group.items.add(
          _Segment(line, tags, segmentKey, map, segmentSequence(line), ad),
        );
        group.duration += duration;
        tags = [];
        duration = 0;
        segmentIndex += BigInt.one;
      }
    }
    if (group.items.isNotEmpty) groups.add(group);
    for (final group in groups) {
      group.summarize();
    }
    final ads = List.filled(groups.length, false);
    if (options.enableFilter) {
      if (options.filterMiddleAd) {
        for (var i = 1; i < groups.length - 1; i++) {
          final prev = groups[i - 1], curr = groups[i], next = groups[i + 1];
          if (!curr.boundary ||
              !next.boundary ||
              curr.duration > options.maxMiddleAdDuration) {
            continue;
          }
          final before = prev.items.last.seq, after = next.items.first.seq;
          final detour =
              before != null &&
              after != null &&
              after - before == BigInt.one &&
              (curr.items.every(
                    (item) => item.seq != null && item.seq! > after,
                  ) ||
                  curr.items.every(
                    (item) => item.seq != null && item.seq! < before,
                  ));
          final outlier =
              prev.max != null &&
              curr.min != null &&
              next.min != null &&
              ((curr.min! - prev.max! > BigInt.from(50) &&
                      curr.max! - next.min! > BigInt.from(50) &&
                      next.min! - prev.max! >= BigInt.zero &&
                      next.min! - prev.max! <= BigInt.from(15)) ||
                  (curr.min! >= BigInt.from(10000) &&
                      prev.max! < BigInt.from(2000) &&
                      next.min! < BigInt.from(2000)));
          ads[i] =
              detour ||
              outlier ||
              (curr.duration <= 20 &&
                  curr.items.length <= 6 &&
                  prev.items.length >= 8 &&
                  next.items.length >= 8);
        }
      }
      if (options.filterHeadAd && groups.length >= 2 && !ads[1]) {
        final head = groups[0], next = groups[1];
        ads[0] =
            head.duration <= options.maxHeadAdDuration &&
            head.min != null &&
            next.min != null &&
            ((head.min! > BigInt.from(1000) && next.min! <= BigInt.from(5)) ||
                (next.boundary && head.max! >= next.min!));
      }
      if (options.filterMiddleAd && groups.length >= 2) {
        final last = groups.last, prev = groups[groups.length - 2];
        ads[groups.length - 1] =
            !ads[groups.length - 2] &&
            last.boundary &&
            last.duration <= options.maxMiddleAdDuration &&
            last.min != null &&
            prev.max != null &&
            last.min! - prev.max! > BigInt.from(100);
      }
    }
    final output = [...header];
    var emittedKey = '', emittedMap = '';
    _Segment? previous;
    var previousIndex = -1, kept = 0;
    for (var i = 0; i < groups.length; i++) {
      if (ads[i]) continue;
      final curr = groups[i];
      final items = curr.items.where((item) => !item.ad).toList();
      if (items.isEmpty) continue;
      final difference = previous?.seq != null && items.first.seq != null
          ? items.first.seq! - previous!.seq!
          : null;
      if (curr.boundary &&
          previous != null &&
          !(i > previousIndex + 1 &&
              difference != null &&
              difference >= BigInt.zero &&
              difference <= BigInt.two)) {
        output.add('#EXT-X-DISCONTINUITY');
      }
      for (final item in items) {
        if (item.key.isNotEmpty && item.key != emittedKey) {
          output.add(item.key);
          emittedKey = item.key;
        }
        if (item.map.isNotEmpty && item.map != emittedMap) {
          output.add(item.map);
          emittedMap = item.map;
        }
        output.addAll([...item.tags, item.uri]);
        kept++;
      }
      previous = items.last;
      previousIndex = i;
    }
    if (kept == 0 && segmentIndex > BigInt.zero) {
      return clean(
        text,
        origin,
        options: const M3u8CleanOptions(enableFilter: false),
      );
    }
    return [...output, ...footer].join('\n');
  }
}
