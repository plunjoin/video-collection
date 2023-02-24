import 'package:http/http.dart' as http;

import 'm3u8_cleaner.dart';
import 'playlist_fetcher_native.dart'
    if (dart.library.js_interop) 'playlist_fetcher_web.dart';
import 'playlist_storage_native.dart'
    if (dart.library.js_interop) 'playlist_storage_web.dart';

/// 每次播放持有一个会话；客户端直连源站，资源仅存在于本机。
class ClientPlaylistService {
  final PlaylistFetcher _fetcher;
  final _storage = PlaylistStorage();
  final _cache = <Uri, Future<String>>{};
  bool _disposed = false;

  ClientPlaylistService({http.Client? client})
    : _fetcher = PlaylistFetcher(client: client);

  Future<String> prepare(String url) async {
    try {
      return await _visit(Uri.parse(url), []);
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  Future<String> _visit(Uri uri, List<Uri> parents) {
    if (_disposed) throw StateError('Playlist session disposed');
    if (parents.contains(uri) || parents.length > 8) {
      throw const FormatException('Playlist nesting limit');
    }
    if (_cache.containsKey(uri)) return _cache[uri]!;
    if (_cache.length >= 64) {
      throw const FormatException('Playlist count limit');
    }
    return _cache[uri] = _load(uri, [...parents, uri]);
  }

  Future<String> _load(Uri uri, List<Uri> parents) async {
    // fetcher 返回最终地址，重定向后的相对路径仍指向源站。
    final (:content, :origin) = await _fetcher.fetch(uri);
    if (_disposed) throw StateError('Playlist session disposed');
    var cleaned = M3u8Cleaner.clean(content, origin);
    if (M3u8Cleaner.isMaster(content)) {
      final result = <String>[];
      for (final line in cleaned.split('\n')) {
        if (!line.startsWith('#')) {
          result.add(await _visit(Uri.parse(line), parents));
        } else if (RegExp(r'^#EXT-X-(?:MEDIA|I-FRAME-STREAM-INF):')
                .hasMatch(line) &&
            M3u8Cleaner.uriAttribute.hasMatch(line)) {
          final match = M3u8Cleaner.uriAttribute.firstMatch(line)!;
          final child = await _visit(Uri.parse(match[1]!), parents);
          result.add(line.replaceRange(match.start, match.end, 'URI="$child"'));
        } else {
          result.add(line);
        }
      }
      cleaned = result.join('\n');
    } else if (!content.contains('#EXT-X-ENDLIST')) {
      throw const FormatException('Live playlist requires remote refresh');
    }
    if (_disposed) throw StateError('Playlist session disposed');
    final local = await _storage.write(cleaned);
    if (_disposed) {
      await _storage.dispose();
      throw StateError('Playlist session disposed');
    }
    return local;
  }

  Future<void> dispose() async {
    _disposed = true;
    _fetcher.dispose();
    await _storage.dispose();
  }
}
