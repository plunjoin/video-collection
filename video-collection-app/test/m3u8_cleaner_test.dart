import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_collection_app/services/m3u8_cleaner.dart';
import 'package:video_collection_app/services/client_playlist_service.dart';

List<String> segments(String text) => text
    .split('\n')
    .where((line) => line.isNotEmpty && !line.startsWith('#'))
    .toList();

void main() {
  final origin = Uri.parse('https://cdn.example/movie/index.m3u8');
  final cases = jsonDecode(
    File('test/fixtures/m3u8_cases.json').readAsStringSync(),
  ) as List;
  for (final sample in cases) {
    test(sample['name'] as String, () {
      final lines = ['#EXTM3U', '#EXT-X-MEDIA-SEQUENCE:0'];
      final groups = [
        sample['before'] as List,
        sample['middle'] as List,
        sample['after'] as List,
      ];
      for (var index = 0; index < groups.length; index++) {
        if (index > 0 && sample['noBoundary'] != true) {
          lines.add('#EXT-X-DISCONTINUITY');
        }
        for (final seq in groups[index]) {
          lines.addAll([
            '#EXTINF:${index == 1 ? sample['middleDuration'] ?? 4 : 32},',
            'movie$seq.ts',
          ]);
        }
      }
      lines.add('#EXT-X-ENDLIST');
      final cleaned = M3u8Cleaner.clean(
        lines.join('\n'),
        origin,
        options: M3u8CleanOptions(
          enableFilter: sample['enableFilter'] != false,
          filterMiddleAd: sample['filterMiddleAd'] != false,
        ),
      );
      final expected = [
        ...groups[0],
        if (sample['remove'] != true) ...groups[1],
        ...groups[2],
      ].map((seq) => origin.resolve('movie$seq.ts').toString()).toList();
      expect(segments(cleaned), expected);
      expect('#EXTINF:'.allMatches(cleaned).length, expected.length);
      expect(cleaned, contains('#EXT-X-MEDIA-SEQUENCE:0'));
      expect(cleaned, endsWith('#EXT-X-ENDLIST'));
    });
  }

  test('head, middle, tail and keyword filters retain the movie', () {
    const text =
        '#EXTM3U\n#EXTINF:4,\n9001.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n0.ts\n#EXTINF:4,\n1.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n10000.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n2.ts\n#EXTINF:4,\n/ad/promo.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n10001.ts\n#EXT-X-ENDLIST';
    expect(
      segments(M3u8Cleaner.clean(text, origin)),
      ['0.ts', '1.ts', '2.ts'].map((uri) => origin.resolve(uri).toString()),
    );
  });

  test('encryption state and implicit IV survive deletion', () {
    const text =
        '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:10\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:4,\n/ad/0.ts\n#EXTINF:4,\n1.ts\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:4,\n2.ts\n#EXT-X-ENDLIST';
    final cleaned = M3u8Cleaner.clean(text, origin);
    expect(
      cleaned,
      contains(
        'URI="https://cdn.example/movie/key.bin",IV=0x0000000000000000000000000000000b',
      ),
    );
    expect(cleaned, contains('#EXT-X-KEY:METHOD=NONE'));
    expect(segments(cleaned).length, 2);
  });

  test('initialization maps, byte offsets and real discontinuities survive', () {
    const text =
        '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4,\n#EXT-X-BYTERANGE:100@0\nmovie.mp4\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n#EXT-X-BYTERANGE:100\nmovie.mp4\n#EXT-X-ENDLIST';
    final cleaned = M3u8Cleaner.clean(text, origin);
    expect(cleaned, contains('URI="https://cdn.example/movie/init.mp4"'));
    expect(cleaned, contains('#EXT-X-BYTERANGE:100@100'));
    expect(cleaned, contains('#EXT-X-DISCONTINUITY'));
  });

  test('live lists and all-keyword lists retain their segments', () {
    const live = '#EXTM3U\n#EXTINF:4,\n/ad/live.ts';
    expect(segments(M3u8Cleaner.clean(live, origin)).length, 1);
    expect(
      segments(M3u8Cleaner.clean('$live\n#EXT-X-ENDLIST', origin)).length,
      1,
    );
    expect(
      () => M3u8Cleaner.clean('<html>error</html>', origin),
      throwsFormatException,
    );
  });

  test('master, video and audio are fetched directly and local files are released', () async {
    final fetched = <String>[];
    final remote = {
      origin.toString(): '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="audio/index.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=800000,AUDIO="audio"\nvideo/index.m3u8',
      'https://cdn.example/movie/audio/index.m3u8':
          '#EXTM3U\n#EXTINF:4,\nsound.aac\n#EXT-X-ENDLIST',
      'https://cdn.example/movie/video/index.m3u8':
          '#EXTM3U\n#EXTINF:4,\n/ad/promo.ts\n#EXTINF:4,\n1.ts\n#EXT-X-ENDLIST',
    };
    final service = ClientPlaylistService(
      client: MockClient((request) async {
        fetched.add(request.url.toString());
        return http.Response(remote[request.url.toString()]!, 200);
      }),
    );
    final master = File.fromUri(
      Uri.parse(await service.prepare(origin.toString())),
    );
    final text = await master.readAsString();
    final video = File.fromUri(Uri.parse(segments(text).single));
    final audio = File.fromUri(
      Uri.parse(M3u8Cleaner.uriAttribute.firstMatch(text)![1]!),
    );
    expect(fetched.length, 3);
    expect(
      fetched.every((url) => url.startsWith('https://cdn.example/')),
      isTrue,
    );
    expect(
      segments(await video.readAsString()).single,
      'https://cdn.example/movie/video/1.ts',
    );
    expect(
      segments(await audio.readAsString()).single,
      'https://cdn.example/movie/audio/sound.aac',
    );
    await service.dispose();
    await service.dispose();
    expect(await master.exists(), isFalse);
    expect(await audio.exists(), isFalse);
    expect(await video.exists(), isFalse);
  });

  test('redirect resolution uses the final source URL', () async {
    final service = ClientPlaylistService(
      client: MockClient((request) async {
        if (request.url == origin) {
          return http.Response(
            '',
            302,
            headers: {'location': '/redirect/index.m3u8'},
          );
        }
        return http.Response('#EXTM3U\n#EXTINF:4,\n0.ts\n#EXT-X-ENDLIST', 200);
      }),
    );
    final file = File.fromUri(
      Uri.parse(await service.prepare(origin.toString())),
    );
    expect(
      segments(await file.readAsString()).single,
      'https://cdn.example/redirect/0.ts',
    );
    await service.dispose();
  });

  test(
    'cycles, live streams, failed requests and disposed sessions fail safely',
    () async {
      for (final mode in ['cycle', 'live', 'network', 'disposed']) {
        final service = ClientPlaylistService(
          client: MockClient((request) async {
            if (mode == 'network') throw const SocketException('network');
            return http.Response(
              mode == 'cycle'
                  ? '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nindex.m3u8'
                  : '#EXTM3U\n#EXTINF:4,\n0.ts',
              200,
            );
          }),
        );
        if (mode == 'disposed') await service.dispose();
        await expectLater(
          service.prepare(origin.toString()),
          mode == 'disposed' ? throwsStateError : throwsA(isA<Exception>()),
        );
        await service.dispose();
      }
    },
  );
}
