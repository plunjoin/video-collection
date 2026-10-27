import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../widgets/brand_intro.dart';
import '../widgets/update_dialog.dart';
import 'main_scaffold.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _introDone = false;

  @override
  void initState() {
    super.initState();
    // 启动后自动检查更新 (默认 6 小时内不重复), 桌面端会自动后台下载安装包
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppStateProvider>().startAutoUpdateCheck();
    });
  }

  /// 自动检查结果提示: 强制更新直接弹窗; 后台下载完成后提示安装
  void _maybePromptUpdate(AppStateProvider state) {
    final prompt = state.autoPromptUpdate;
    if (prompt != null) {
      state.consumeAutoPromptUpdate();
      showUpdateDialog(context, prompt);
      return;
    }
    final info = state.latestUpdateInfo;
    if (state.updateReadyToInstall && info != null) {
      state.consumeUpdateReadyPrompt();
      showUpdateDialog(context, info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybePromptUpdate(appState);
    });
    final ready = appState.isInitialized;
    if (ready && _introDone) return const MainScaffold();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: BrandIntro(
            progress: ready ? 1 : null,
            onCompleted: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _introDone = true);
              });
            },
          ),
        ),
      ),
    );
  }
}
