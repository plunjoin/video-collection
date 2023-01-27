import 'dart:io';

class PlaylistStorage {
  Directory? _directory;
  int _index = 0;
  Future<String> write(String content) async {
    _directory ??= await Directory.systemTemp.createTemp('bllii-playlists-');
    final file = File('${_directory!.path}/playlist-${_index++}.m3u8');
    await file.writeAsString(content, flush: true);
    return file.uri.toString();
  }

  Future<void> dispose() async {
    final directory = _directory;
    _directory = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
