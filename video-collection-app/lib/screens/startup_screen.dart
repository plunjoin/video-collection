import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../widgets/brand_intro.dart';
import 'main_scaffold.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _introDone = false;
  @override
  Widget build(BuildContext context) {
    final ready = context.watch<AppStateProvider>().isInitialized;
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
