import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// 桌面端「下载安装包 → 静默安装 → 重启应用」更新服务
///
/// 仅支持 Windows 的 Inno Setup 安装包 (setup.exe):
/// 下载到系统临时目录, 安装时通过独立 PowerShell 进程
/// 以 `/VERYSILENT` 等参数等待安装完成后重新拉起应用, 随后当前进程退出。
class InstallerUpdateService {
  InstallerUpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const List<String> _silentArgs = [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/SP-',
    '/CLOSEAPPLICATIONS',
  ];

  /// 是否桌面端 (Windows / macOS / Linux)
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 当前平台是否支持「安装包直装」更新 (仅 Windows + .exe 安装包)
  static bool canInstallWithInstaller(String downloadUrl) {
    if (!Platform.isWindows) return false;
    final url = downloadUrl.trim().toLowerCase();
    return url.endsWith('.exe');
  }

  /// 下载安装包到临时目录, 返回本地文件
  /// [onProgress] 回调 0.0 ~ 1.0; 服务端未返回 Content-Length 时只回调 0/1
  Future<File> downloadInstaller(
    String url,
    String version, {
    void Function(double progress)? onProgress,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw const UpdateDownloadException('下载地址为空');

    final request = http.Request('GET', Uri.parse(trimmed));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw UpdateDownloadException(
        '服务器返回 HTTP ${response.statusCode}',
      );
    }

    final total = response.contentLength ?? 0;
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'bllii_update_$version.exe',
    );
    if (file.existsSync()) file.deleteSync();

    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
    } catch (e) {
      throw UpdateDownloadException('下载中断: $e');
    } finally {
      await sink.close();
    }

    if (total > 0 && received != total) {
      file.deleteSync();
      throw const UpdateDownloadException('下载不完整, 请重试');
    }
    onProgress?.call(1);
    return file;
  }

  /// 执行安装并重启应用
  ///
  /// 启动一个独立进程等待安装完成后重新打开应用, 然后立即退出当前进程,
  /// 让安装包能够正常覆盖正在运行的程序文件。
  Future<void> installAndRelaunch(String installerPath) async {
    if (!Platform.isWindows) {
      throw const UpdateDownloadException('安装包直装更新仅支持 Windows');
    }
    final file = File(installerPath);
    if (!file.existsSync()) {
      throw const UpdateDownloadException('安装包不存在, 请重新下载');
    }

    final appExe = Platform.resolvedExecutable;
    // PowerShell 单引号字符串: 内部单引号需翻倍转义
    String psQuote(String value) => "'${value.replaceAll("'", "''")}'";

    final script =
        'Start-Process -FilePath ${psQuote(file.path)} '
        '-ArgumentList ${_silentArgs.map(psQuote).join(',')} -Wait; '
        'Start-Process -FilePath ${psQuote(appExe)}';

    await Process.start(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    // 给子进程留出启动时间再退出, 避免极端情况下安装器尚未拉起
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }
}

class UpdateDownloadException implements Exception {
  final String message;
  const UpdateDownloadException(this.message);
  @override
  String toString() => message;
}
