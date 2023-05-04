import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../widgets/brand_controls.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/desktop_window_title_bar.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _nickname = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppStateProvider>().authenticate(
        _username.text,
        _password.text,
        nickname: _register ? _nickname.text : null,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        DesktopWindowTitleBar(
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
        Expanded(
          child: Scaffold(
            appBar: BrandAppBar(title: Text(_register ? '注册账号' : '登录账号')),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: 400,
                  child: Form(
                    key: _form,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: BrandLogo(width: 160)),
                          const SizedBox(height: 28),
                          const Text('登录后，在不同设备继续你的故事。'),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _username,
                            enabled: !_busy,
                            autofillHints: const [AutofillHints.username],
                            decoration: const InputDecoration(labelText: '用户名'),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? '请输入用户名' : null,
                          ),
                          const SizedBox(height: 14),
                          if (_register) ...[
                            TextFormField(
                              controller: _nickname,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                labelText: '昵称（选填）',
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            autofillHints: [
                              _register
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: const InputDecoration(labelText: '密码'),
                            onFieldSubmitted: (_) => _submit(),
                            validator: (v) => v == null || v.isEmpty
                                ? '请输入密码'
                                : _register && v.trim().length < 6
                                ? '密码至少 6 位'
                                : null,
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: Text(
                              _busy
                                  ? '请稍候…'
                                  : _register
                                  ? '注册并登录'
                                  : '登录',
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _register = !_register;
                                    _error = null;
                                  }),
                            child: Text(_register ? '已有账号，去登录' : '还没有账号？注册'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
