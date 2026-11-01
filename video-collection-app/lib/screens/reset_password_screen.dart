import 'dart:async';

import '../ui/kit.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../theme/brand_icons.dart';
import '../widgets/brand_controls.dart';

/// 忘记密码：通过已绑定的邮箱 / 手机接收验证码后重置密码。
/// 重置成功后服务端会下线全部设备，需要用新密码重新登录。
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _target = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String _channel = 'email';
  bool _sending = false;
  bool _busy = false;
  int _countdown = 0;
  Timer? _timer;
  String? _error;
  String? _info;

  bool get _isEmail => _channel == 'email';

  @override
  void dispose() {
    _timer?.cancel();
    _target.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdown -= 1);
      if (_countdown <= 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    if (_sending || _countdown > 0) return;
    final target = _target.text.trim();
    if (target.isEmpty) {
      setState(() => _error = _isEmail ? '请输入邮箱地址' : '请输入手机号');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _info = null;
    });
    var devCode = '';
    final error = await context.read<AppStateProvider>().sendCode(
      channel: _channel,
      target: target,
      purpose: 'reset',
      outDevCode: (code) => devCode = code,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      if (error == null) {
        _info = devCode.isEmpty
            ? '验证码已发送，10 分钟内有效'
            : '验证码已发送（联调验证码：$devCode）';
      }
    });
    if (error == null) {
      if (devCode.isNotEmpty) _code.text = devCode;
      _startCountdown();
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await context.read<AppStateProvider>().resetPassword(
      channel: _channel,
      target: _target.text.trim(),
      code: _code.text.trim(),
      newPassword: _password.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Scaffold(
              appBar: const BrandAppBar(title: Text('找回密码')),
              body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          '输入绑定过的邮箱或手机号，我们会发送 6 位验证码。'
                          '重置成功后所有设备都会下线。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 18),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'email',
                              label: Text('邮箱'),
                              icon: BrandIcon(BIcons.mail, size: 16),
                            ),
                            ButtonSegment(
                              value: 'phone',
                              label: Text('手机号'),
                              icon: BrandIcon(BIcons.message, size: 16),
                            ),
                          ],
                          selected: {_channel},
                          onSelectionChanged: (selection) {
                            setState(() {
                              _channel = selection.first;
                              _error = null;
                              _info = null;
                              _code.clear();
                            });
                          },
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _target,
                          enabled: !_busy,
                          keyboardType: _isEmail
                              ? TextInputType.emailAddress
                              : TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: _isEmail ? '邮箱' : '手机号',
                            hintText: _isEmail ? 'you@example.com' : '11 位手机号',
                            prefixIcon: BrandIcon(
                              _isEmail ? BIcons.mail : BIcons.message,
                            ),
                          ),
                          validator: (value) =>
                              (value?.trim().isEmpty ?? true) ? '请填写联系方式' : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _code,
                                enabled: !_busy,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '验证码',
                                  hintText: '6 位数字',
                                ),
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (!RegExp(r'^\d{6}$').hasMatch(text)) {
                                    return '请输入 6 位数字验证码';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton(
                                onPressed: _sending || _countdown > 0
                                    ? null
                                    : _send,
                                child: Text(
                                  _countdown > 0
                                      ? '${_countdown}s'
                                      : _sending
                                      ? '发送中…'
                                      : '获取验证码',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(
                            labelText: '新密码',
                            hintText: '至少 6 位',
                            prefixIcon: BrandIcon(BIcons.lock),
                          ),
                          validator: (value) => (value ?? '').length < 6
                              ? '新密码不能少于 6 位'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirm,
                          enabled: !_busy,
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(
                            labelText: '确认新密码',
                            prefixIcon: BrandIcon(BIcons.check),
                          ),
                          validator: (value) => value != _password.text
                              ? '两次输入的新密码不一致'
                              : null,
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (_info != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              _info!,
                              style: const TextStyle(color: Color(0xFF2E9E6B)),
                            ),
                          ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(_busy ? '提交中…' : '重置密码'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '还没绑定邮箱或手机？先登录，在「设置 → 账号安全」里绑定。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
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
}
