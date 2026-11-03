import 'dart:async';
import 'dart:js_interop';

import 'package:http/http.dart' as http;

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}

@JS()
extension type _FetchOptions._(JSObject _) implements JSObject {
  external factory _FetchOptions({JSObject signal});
}

@JS()
extension type _FetchResponse._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external String get url;
  external JSPromise<JSString> text();
}

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(String url, _FetchOptions options);

class PlaylistFetcher {
  final _controllers = <_AbortController>[];
  bool _disposed = false;
  PlaylistFetcher({http.Client? client});

  Future<({String content, Uri origin})> fetch(Uri uri) async {
    if (_disposed) throw StateError('Playlist session disposed');
    final controller = _AbortController();
    _controllers.add(controller);
    final timer = Timer(const Duration(seconds: 10), () => controller.abort());
    try {
      final response = await _fetch(
        uri.toString(),
        _FetchOptions(signal: controller.signal),
      ).toDart;
      if (!response.ok) throw StateError('Playlist HTTP ${response.status}');
      final content = (await response.text().toDart).toDart;
      return (content: content, origin: Uri.parse(response.url));
    } finally {
      timer.cancel();
      _controllers.remove(controller);
    }
  }

  void dispose() {
    _disposed = true;
    for (final controller in _controllers) {
      controller.abort();
    }
    _controllers.clear();
  }
}
