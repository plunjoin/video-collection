import 'dart:js_interop';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSString> parts, _BlobOptions options);
}

@JS()
extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

@JS('URL.createObjectURL')
external String _createObjectURL(_Blob blob);
@JS('URL.revokeObjectURL')
external void _revokeObjectURL(String url);

class PlaylistStorage {
  final _urls = <String>[];
  Future<String> write(String content) async {
    final url = _createObjectURL(
      _Blob(
        [content.toJS].toJS,
        _BlobOptions(type: 'application/vnd.apple.mpegurl'),
      ),
    );
    _urls.add(url);
    // MediaKit Web 依据 m3u8 标识选择 HLS 引擎，fragment 不参与 Blob 查找。
    return '$url#playlist.m3u8';
  }

  Future<void> dispose() async {
    for (final url in _urls) {
      _revokeObjectURL(url);
    }
    _urls.clear();
  }
}
