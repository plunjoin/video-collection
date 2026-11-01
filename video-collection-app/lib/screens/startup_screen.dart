import '../ui/kit.dart';
import 'package:provider/provider.dart';

import '../models/video_model.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../widgets/brand_intro.dart';
import '../widgets/update_dialog.dart';
import 'main_scaffold.dart';
import 'player_screen.dart';

class StartupScreen extends StatefulWidget {
  /// 命令行深链：`--open-player=视频ID` 启动后直达播放页
  final String? openPlayerVideoId;

  const StartupScreen({super.key, this.openPlayerVideoId});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _introDone = false;
  bool _deepLinkHandled = false;

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

  /// 深链：加载影片详情并直达播放页
  Future<void> _handleDeepLink() async {
    final id = widget.openPlayerVideoId;
    if (_deepLinkHandled || id == null || id.trim().isEmpty) return;
    _deepLinkHandled = true;
    final videoId = int.tryParse(id.trim());
    if (videoId == null || videoId <= 0) return;
    try {
      final result = await ApiService().getVideoDetail(videoId);
      final video = result['video'] as VideoRecord?;
      if (!mounted || video == null) return;
      final groups = video.playGroups;
      var group = 0;
      if (groups.isNotEmpty && groups[group].episodes.isEmpty) {
        group = groups.indexWhere((g) => g.episodes.isNotEmpty);
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            video: video,
            initialGroupIndex: group < 0 ? 0 : group,
          ),
        ),
      );
    } catch (_) {
      // 深链失败静默降级为普通首页
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybePromptUpdate(appState);
        if (appState.isInitialized && _introDone) _handleDeepLink();
      }
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
