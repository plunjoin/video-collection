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
  late final TextEditingController _blocked;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppStateProvider>();
    _address = TextEditingController(text: state.apiBaseUrl);
    _blocked = TextEditingController(text: state.danmakuBlocked);
  }

  @override
  void dispose() {
    _address.dispose();
    _blocked.dispose();
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

  Future<void> _clearSearch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => BrandDialog(
        title: const Text('清空搜索记录'),
        content: const Text('本机保存的搜索关键词会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AppStateProvider>().clearSearchHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('搜索记录已清空')));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final config = state.siteConfig;
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
                      _heading('外观模式'),
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
                      _heading('主题颜色'),
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
                      _heading('播放'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自动播放下一集'),
                        subtitle: const Text('当前一集结束后停留 3 秒，再进入下一集'),
                        value: state.autoPlayNext,
                        onChanged: state.setAutoPlayNext,
                      ),
                      const SizedBox(height: 8),
                      const Text('默认倍速'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final speed in [0.75, 1.0, 1.25, 1.5, 2.0])
                            ChoiceChip(
                              label: Text(speed == 1 ? '正常' : '${speed}x'),
                              selected: _near(state.playbackSpeed, speed),
                              onSelected: (_) => state.setPlaybackSpeed(speed),
                            ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      _heading('弹幕'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('默认打开弹幕'),
                        subtitle: const Text('播放时在画面上按时间轴滚动显示'),
                        value: state.danmakuEnabled,
                        onChanged: state.setDanmakuEnabled,
                      ),
                      Text('不透明度 ${(state.danmakuOpacity * 100).round()}%'),
                      Slider(
                        value: state.danmakuOpacity,
                        min: 0.2,
                        max: 1,
                        onChanged: state.setDanmakuOpacity,
                      ),
                      const Text('字号'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final option in [
                            (0.85, '小'),
                            (1.0, '标准'),
                            (1.25, '大'),
                          ])
                            ChoiceChip(
                              label: Text(option.$2),
                              selected: _near(
                                state.danmakuFontScale,
                                option.$1,
                              ),
                              onSelected: (_) =>
                                  state.setDanmakuFontScale(option.$1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('速度'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final option in [
                            (0.75, '慢'),
                            (1.0, '正常'),
                            (1.35, '快'),
                          ])
                            ChoiceChip(
                              label: Text(option.$2),
                              selected: _near(state.danmakuSpeed, option.$1),
                              onSelected: (_) =>
                                  state.setDanmakuSpeed(option.$1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('显示区域'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final option in [
                            (0.3, '顶部少量'),
                            (0.5, '上半屏'),
                            (0.85, '大部分画面'),
                          ])
                            ChoiceChip(
                              label: Text(option.$2),
                              selected: _near(state.danmakuArea, option.$1),
                              onSelected: (_) =>
                                  state.setDanmakuArea(option.$1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _blocked,
                        decoration: const InputDecoration(
                          labelText: '屏蔽词',
                          hintText: '用逗号分开，例如：剧透，广告',
                          prefixIcon: Icon(Icons.block_rounded),
                        ),
                        onSubmitted: state.setDanmakuBlocked,
                        onEditingComplete: () =>
                            state.setDanmakuBlocked(_blocked.text),
                      ),
                      const SizedBox(height: 32),
                      _heading('数据'),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_rounded),
                        title: const Text('搜索记录'),
                        subtitle: Text(
                          state.searchHistory.isEmpty
                              ? '还没有搜索记录'
                              : '已保存 ${state.searchHistory.length} 条',
                        ),
                        trailing: TextButton(
                          onPressed: state.searchHistory.isEmpty
                              ? null
                              : _clearSearch,
                          child: const Text('清空'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _heading('关于'),
                      const SizedBox(height: 8),
                      Text(config.siteName),
                      if (config.siteSubtitle.isNotEmpty)
                        Text(config.siteSubtitle),
                      const SizedBox(height: 6),
                      const Text('客户端版本 1.0.0'),
                      if (config.siteContactEmail.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(config.siteContactEmail),
                      ],
                      if (config.siteAnnouncement.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(config.siteAnnouncement),
                      ],
                      if (allowsApiBaseUrlOverride) ...[
                        const SizedBox(height: 32),
                        _heading('服务端'),
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
                              onPressed: _busy
                                  ? null
                                  : () => _check(save: false),
                              child: const Text('测试连接'),
                            ),
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _check(save: true),
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

  Widget _heading(String text) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }

  bool _near(double left, double right) => (left - right).abs() < 0.02;
}
