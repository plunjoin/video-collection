import 'package:provider/provider.dart';

import '../../shared/models/video_model.dart';
import '../../shared/providers/app_state_provider.dart';
import '../../shared/services/api_service.dart';
import '../../shared/ui/kit.dart';
import '../../shared/widgets/brand_intro.dart';
import '../../shared/widgets/update_dialog.dart';
import '../app_shell.dart';
import 'player_mobile_page.dart';

class StartupMobilePage extends StatefulWidget {
  /// 命令行深链：`--open-player=视频ID` 启动后直达播放页
  final String? openPlayerVideoId;

  const StartupMobilePage({super.key, this.openPlayerVideoId});

  @override
  State<StartupMobilePage> createState() => _StartupMobilePageState();
}

class _StartupMobilePageState extends State<StartupMobilePage> {
  bool _introDone = false;
  bool _deepLinkHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppStateProvider>().startAutoUpdateCheck();
    });
  }

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
          builder: (_) => PlayerMobilePage(
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
    if (ready && _introDone) return const MobileShell();
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
