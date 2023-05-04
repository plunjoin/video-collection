import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../widgets/brand_controls.dart';
import '../widgets/desktop_window_title_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _address;
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _address = TextEditingController(
      text: context.read<AppStateProvider>().apiBaseUrl,
    );
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _check({required bool save}) async {
    final address = _address.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(address);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      setState(() => _message = '请输入有效的 http 或 https 服务端地址');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final state = context.read<AppStateProvider>();
    final ok = save
        ? await state.updateApiBaseUrl(address)
        : await ApiService().testConnection(
            normalizeApiBaseUrlForPlatform(address),
          );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok ? (save ? '服务端配置已保存' : '连接正常') : '连接失败，请检查地址与网络，原配置已保留';
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    return Scaffold(
      body: Column(
        children: [
          DesktopWindowTitleBar(
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),
          Expanded(
            child: Scaffold(
              appBar: const BrandAppBar(title: Text('设置')),
              body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        '外观模式',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final option in [
                            (ThemeMode.light, '浅色'),
                            (ThemeMode.dark, '深色'),
                            (ThemeMode.system, '跟随系统'),
                          ])
                            BrandPill(
                              label: Text(option.$2),
                              selected: state.themeMode == option.$1,
                              onPressed: () => state.setThemeMode(option.$1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        '主题颜色',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final option in [
                            ('blue', '晴空蓝', const Color(0xFF597BEA)),
                            ('pink', '樱花粉', const Color(0xFFC64C91)),
                            ('purple', '梦境紫', const Color(0xFF8464D4)),
                          ])
                            ChoiceChip(
                              label: Text(option.$2),
                              avatar: CircleAvatar(
                                backgroundColor: option.$3,
                                radius: 8,
                              ),
                              selected: state.accent == option.$1,
                              onSelected: (_) => state.setAccent(option.$1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Text(
                        '服务端',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _address,
                        enabled: !_busy,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '服务端地址',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('更换服务端后需要重新登录。测试连接不会修改已保存的地址。'),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          OutlinedButton(
                            onPressed: _busy ? null : () => _check(save: false),
                            child: const Text('测试连接'),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : () => _check(save: true),
                            child: Text(_busy ? '连接中…' : '保存'),
                          ),
                        ],
                      ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_message!),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
