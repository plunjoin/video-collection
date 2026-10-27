import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/update_model.dart';
import '../providers/app_state_provider.dart';
import '../services/installer_update_service.dart';
import '../services/update_service.dart';
import '../theme/app_colors.dart';
import 'brand_controls.dart';
import 'brand_widgets.dart';

/// 弹出版本更新弹窗
Future<void> showUpdateDialog(BuildContext context, AppUpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !info.forceUpdate,
    builder: (context) => UpdateDialog(info: info),
  );
}

class UpdateDialog extends StatelessWidget {
  final AppUpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    if (!info.hasUpdate) {
      return BrandDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: dark ? 0.25 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, color: primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('已是最新版本'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 v${UpdateService.currentVersion} 已经是最新版本，暂无可用更新。',
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: dark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1B2333) : const Color(0xFFF4F7FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '尽情畅享高清番剧与沉浸播放体验！',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: dark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好的'),
          ),
        ],
      );
    }

    // 桌面端 Windows 且下载链接为 .exe 安装包时, 走「下载 -> 静默安装」流程
    final installerMode = InstallerUpdateService.canInstallWithInstaller(
      info.downloadUrl,
    );

    return PopScope(
      canPop: !info.forceUpdate,
      child: BrandDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4B9FFF), Color(0xFF9A83FF)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.rocket_launch_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('发现新版本'),
                  Text(
                    'v${info.version}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: primary,
                    ),
                  ),
                ],
              ),
            ),
            if (info.forceUpdate)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '必须更新',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.redAccent,
                  ),
                ),
              ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 版本对比区域
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1B2333) : const Color(0xFFF4F7FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前版本',
                          style: TextStyle(
                            fontSize: 11,
                            color: dark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'v${UpdateService.currentVersion}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: primary.withValues(alpha: 0.7),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '最新版本',
                          style: TextStyle(
                            fontSize: 11,
                            color: dark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'v${info.version}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '更新内容',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF151C28) : const Color(0xFFF9FAFD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: dark
                      ? AppColors.darkBorder
                      : const Color(0xFFE8EEFA),
                ),
              ),
              child: SingleChildScrollView(
                child: Text(
                  info.changelog.trim().isEmpty
                      ? '性能提升与细节优化'
                      : info.changelog.trim(),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ),
            // 安装包模式: 下载进度 / 状态提示
            if (installerMode) ...[
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final state = context.watch<AppStateProvider>();
                  if (state.downloadingUpdate) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: state.updateDownloadProgress > 0
                                ? state.updateDownloadProgress
                                : null,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '正在下载安装包 ${(state.updateDownloadProgress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: dark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    );
                  }
                  if (state.downloadedInstallerPath != null) {
                    return Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '安装包已下载完成，点击「安装并重启」后将自动完成更新',
                            style: TextStyle(
                              fontSize: 12,
                              color: dark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  if (state.updateDownloadError != null) {
                    return Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 16, color: Colors.redAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            state.updateDownloadError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
            if (info.publishTime != null && info.publishTime!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '发布时间: ${info.publishTime}',
                  style: TextStyle(
                    fontSize: 11,
                    color: dark
                        ? AppColors.darkTextSecondary.withValues(alpha: 0.6)
                        : AppColors.lightTextSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('暂不更新'),
            ),
          if (info.downloadUrl.isNotEmpty)
            OutlinedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: info.downloadUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('下载链接已复制到剪贴板')),
                );
              },
              child: const Text('复制链接'),
            ),
          Builder(
            builder: (context) {
              if (!installerMode) {
                // 移动端 / 非安装包链接: 打开浏览器下载 (保持原行为)
                if (info.downloadUrl.isEmpty) {
                  return FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('确定'),
                  );
                }
                return FilledButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('立即更新'),
                  onPressed: () async {
                    final ok = await UpdateService.launchUpdate(
                      info.downloadUrl,
                    );
                    if (!ok && context.mounted) {
                      Clipboard.setData(
                        ClipboardData(text: info.downloadUrl),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('无法自动唤起浏览器，下载链接已复制'),
                        ),
                      );
                    }
                  },
                );
              }

              // 安装包模式: 下载 -> 安装并重启
              final state = context.watch<AppStateProvider>();
              if (state.downloadingUpdate) {
                return FilledButton.icon(
                  icon: const BrandSpinner(size: 16),
                  label: Text(
                    '下载中 ${(state.updateDownloadProgress * 100).toStringAsFixed(0)}%',
                  ),
                  onPressed: null,
                );
              }
              if (state.downloadedInstallerPath != null) {
                return FilledButton.icon(
                  icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                  label: const Text('安装并重启'),
                  onPressed: () => state.installUpdate(),
                );
              }
              return FilledButton.icon(
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  state.updateDownloadError != null ? '重新下载' : '下载并安装',
                ),
                onPressed: () => state.downloadUpdate(),
              );
            },
          ),
        ],
      ),
    );
  }
}
