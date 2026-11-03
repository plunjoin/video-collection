import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 「下载安装包 → 站内安装」更新服务
///
/// - Windows: Inno Setup 安装包 (setup.exe)。下载到系统临时目录,
///   安装时通过独立 PowerShell 进程以 `/VERYSILENT` 等参数等待
///   安装完成后重新拉起应用, 随后当前进程退出。
/// - Android: APK 下载到应用缓存, 下完通过 MethodChannel 拉起系统
///   安装界面。系统不允许静默覆盖, 用户需在安装界面点一次确认。
class InstallerUpdateService {
  InstallerUpdateService({http.Client? client, MethodChannel? apkChannel})
      : _client = client ?? http.Client(),
        _apkChannel = apkChannel ?? const MethodChannel('bllii/apk_installer');

  final http.Client _client;
  final MethodChannel _apkChannel;

  /// 当前平台安装包后缀。其他平台返回空, 表示不走站内安装。
  static String installerExtensionForPlatform() {
    if (kIsWeb) return '';
    if (Platform.isWindows) return '.exe';
    if (Platform.isAndroid) return '.apk';
    return '';
  }

  /// 静默安装参数。刻意不带 /SUPPRESSMSGBOXES:
  /// 安装器初始化失败(如安全软件拦截、签名/版本校验)时必须把错误弹窗露出来,
  /// 否则静默流程会无声中止,用户只看到"更新后版本没变"。
  static List<String> silentArgs(String logPath) => [
        '/VERYSILENT',
        '/NORESTART',
        '/SP-',
        '/CLOSEAPPLICATIONS',
        '/LOG=$logPath',
      ];

  /// 手动向导安装参数:展示完整向导,便于看清报错并手动完成安装。
  static List<String> wizardArgs(String logPath) => [
        '/NORESTART',
        '/SP-',
        '/CLOSEAPPLICATIONS',
        '/LOG=$logPath',
      ];

  /// 是否桌面端 (Windows / macOS / Linux)
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 当前平台是否支持「安装包直装」更新
  /// Windows 只认 .exe, Android 只认 .apk; 其余平台 (含 iOS) 不支持。
  static bool canInstallWithInstaller(String downloadUrl) {
    final ext = installerExtensionForPlatform();
    if (ext.isEmpty) return false;
    final url = downloadUrl.trim().toLowerCase();
    final path = Uri.tryParse(url)?.path ?? url;
    return path.endsWith(ext);
  }

  /// Android 下完要自动打开系统安装界面; Windows 留着等用户点「安装并重启」。
  static bool get installsAutomatically => !kIsWeb && Platform.isAndroid;

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
    final file = File(await installerFilePath(version));
    final parent = file.parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
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

  /// 安装包落盘路径。
  /// Android 放应用缓存的 updates/ 下, 与 FileProvider 的 cache-path 对齐;
  /// 其余平台放系统临时目录。
  Future<String> installerFilePath(String version) async {
    final ext = installerExtensionForPlatform();
    final name = 'bllii_update_$version${ext.isEmpty ? '.bin' : ext}';
    if (!kIsWeb && Platform.isAndroid) {
      final cache = await getTemporaryDirectory();
      return '${cache.path}${Platform.pathSeparator}updates'
          '${Platform.pathSeparator}$name';
    }
    return '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
  }

  /// 执行安装并重启应用
  ///
  /// [silent] 为 true 时走静默覆盖安装;为 false 时弹出完整安装向导
  /// (静默失败后的兜底路径,用户可以直接看到安装器的报错)。
  /// 启动一个独立进程等待安装完成后重新打开应用, 然后立即退出当前进程,
  /// 让安装包能够正常覆盖正在运行的程序文件。
  Future<void> installAndRelaunch(
    String installerPath, {
    bool silent = true,
  }) async {
    final file = File(installerPath);
    if (!file.existsSync()) {
      throw const UpdateDownloadException('安装包不存在, 请重新下载');
    }
    if (!kIsWeb && Platform.isAndroid) {
      await _installApk(file);
      return;
    }
    if (kIsWeb || !Platform.isWindows) {
      throw const UpdateDownloadException('当前平台不支持安装包直装更新');
    }

    final logPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}bllii_setup_update.log';
    final args = [
      ...(silent ? silentArgs(logPath) : wizardArgs(logPath)),
    ];

    final appExe = Platform.resolvedExecutable;
    // PowerShell 单引号字符串: 内部单引号需翻倍转义
    String psQuote(String value) => "'${value.replaceAll("'", "''")}'";

    final script =
        'Start-Process -FilePath ${psQuote(file.path)} '
        '-ArgumentList ${args.map(psQuote).join(',')} -Wait; '
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

  /// 拉起系统 APK 安装界面。
  /// Android 8+ 若没有「安装未知应用」权限, 先打开系统设置让用户授权,
  /// 授权后再点一次「立即安装」即可。
  Future<void> _installApk(File file) async {
    try {
      final allowed =
          await _apkChannel.invokeMethod<bool>('canRequestPackageInstalls');
      if (allowed == false) {
        await _apkChannel.invokeMethod<bool>('openInstallPermissionSettings');
        throw const UpdateDownloadException(
          '请先允许本应用安装未知应用, 开启后再点一次安装',
        );
      }
      await _apkChannel.invokeMethod<bool>('installApk', {'path': file.path});
    } on UpdateDownloadException {
      rethrow;
    } on PlatformException catch (e) {
      throw UpdateDownloadException('无法打开安装界面: ${e.message ?? e.code}');
    }
  }
}

class UpdateDownloadException implements Exception {
  final String message;
  const UpdateDownloadException(this.message);
  @override
  String toString() => message;
}
