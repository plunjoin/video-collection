import 'dart:convert';

import 'package:http/http.dart' as http;

class PlaylistFetcher {
  final http.Client _client;
  PlaylistFetcher({http.Client? client}) : _client = client ?? http.Client();

  Future<({String content, Uri origin})> fetch(Uri uri) async {
    var origin = uri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = http.Request('GET', origin)..followRedirects = false;
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 10));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) {
          throw const FormatException('Redirect without location');
        }
        origin = origin.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        throw StateError('Playlist HTTP ${response.statusCode}');
      }
      return (content: utf8.decode(response.bodyBytes), origin: origin);
    }
    throw const FormatException('Too many playlist redirects');
  }

  void dispose() => _client.close();
}
