import 'dart:async';

import '../../shared/ui/kit.dart';
import 'package:provider/provider.dart';

import '../../shared/providers/app_state_provider.dart';
import '../../shared/theme/brand_icons.dart';
import '../../shared/widgets/brand_controls.dart';
import '../../shared/widgets/brand_widgets.dart';

/// 账号安全：自助修改密码 + 登录设备管理。
/// 改密成功后服务端会吊销其他设备的会话，当前设备保持登录。
class AccountSecurityMobilePage extends StatefulWidget {
  const AccountSecurityMobilePage({super.key});

  @override
  State<AccountSecurityMobilePage> createState() => _AccountSecurityMobilePageState();
}

class _AccountSecurityMobilePageState extends State<AccountSecurityMobilePage> {
  final _form = GlobalKey<FormState>();
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _success;

  List<Map<String, dynamic>> _sessions = const [];
  bool _loadingSessions = true;
  String? _revokingId;

  Map<String, dynamic> _contact = const {};
  bool _loadingContact = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadContact();
  }

  @override
  void dispose() {
    _oldPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final list = await context.read<AppStateProvider>().loadSessions();
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _loadingSessions = false;
    });
  }

  Future<void> _loadContact() async {
    final contact = await context.read<AppStateProvider>().loadContact();
    if (!mounted) return;
    setState(() {
      _contact = contact;
      _loadingContact = false;
    });
  }

  /// 绑定邮箱 / 手机：弹窗内完成「获取验证码 → 提交」。
  Future<void> _openBindDialog({
    required String channel,
    required String label,
    required String hint,
  }) async {
    final bound = await showDialog<bool>(
      context: context,
      builder: (context) => _BindContactDialog(
        channel: channel,
        label: label,
        hint: hint,
      ),
    );
    if (bound == true && mounted) {
      await _loadContact();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label绑定成功')));
    }
  }

  /// 解绑需要二次确认登录密码。
  Future<void> _openUnbindDialog({
    required String channel,
    required String label,
  }) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('解绑$label'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '当前密码',
            prefixIcon: const BrandIcon(BIcons.lock),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认解绑'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      controller.dispose();
      return;
    }
    final error = await context.read<AppStateProvider>().unbindContact(
      channel: channel,
      password: controller.text,
    );
    controller.dispose();
    if (!mounted) return;
    if (error == null) {
      await _loadContact();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label已解绑')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// 注销账号：密码 + 输入「注销」二次确认，成功后退出到上一级。
  Future<void> _confirmDeleteAccount() async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('注销账号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '注销后不可恢复：用户名会被匿名化，邮箱 / 手机 / 头像 / 简介将被清空，'
              '所有设备立即下线。已发布内容会保留，作者显示为「已注销用户」。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '当前密码',
                prefixIcon: BrandIcon(BIcons.lock),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirm,
              decoration: const InputDecoration(
                labelText: '输入「注销」以确认',
                prefixIcon: BrandIcon(BIcons.alert),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('永久注销'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      password.dispose();
      confirm.dispose();
      return;
    }
    if (confirm.text.trim() != '注销') {
      password.dispose();
      confirm.dispose();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入「注销」两个字以确认')));
      return;
    }
    final error = await context.read<AppStateProvider>().deleteAccount(
      password.text,
    );
    password.dispose();
    confirm.dispose();
    if (!mounted) return;
    if (error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('账号已注销')));
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    final result = await context.read<AppStateProvider>().changePassword(
      oldPassword: _oldPassword.text,
      newPassword: _newPassword.text,
    );
    if (!mounted) return;
    if (result.ok) {
      _oldPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      setState(() {
        _busy = false;
        _success = result.revoked > 0
            ? '密码已更新，${result.revoked} 台其他设备已下线'
            : '密码已更新';
      });
      await _loadSessions();
      return;
    }
    setState(() {
      _busy = false;
      _error = result.error;
    });
  }

  Future<void> _revoke(Map<String, dynamic> session) async {
    final id = session['id']?.toString() ?? '';
    if (id.isEmpty || _revokingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下线该设备'),
        content: const Text('该设备需要重新登录才能继续使用当前账号。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认下线'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _revokingId = id);
    final error = await context.read<AppStateProvider>().revokeSession(id);
    if (!mounted) return;
    setState(() {
      _revokingId = null;
      if (error == null) {
        _sessions = _sessions.where((item) => item['id'] != id).toList();
      }
    });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Scaffold(
              appBar: const BrandAppBar(title: Text('账号安全')),
              body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _heading('修改密码'),
                      const SizedBox(height: 6),
                      Text(
                        '修改成功后，其他已登录设备会被自动下线，当前设备保持登录。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 18),
                      Form(
                        key: _form,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _oldPassword,
                              enabled: !_busy,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: '当前密码',
                                prefixIcon: const BrandIcon(BIcons.lock),
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? '显示密码' : '隐藏密码',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: BrandIcon(
                                    _obscure ? BIcons.lock : BIcons.unlock,
                                    size: 19,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  (value ?? '').isEmpty ? '请输入当前密码' : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _newPassword,
                              enabled: !_busy,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: const InputDecoration(
                                labelText: '新密码',
                                hintText: '至少 6 位，不能与原密码相同',
                                prefixIcon: BrandIcon(BIcons.lock),
                              ),
                              validator: (value) {
                                final text = value ?? '';
                                if (text.length < 6) return '新密码不能少于 6 位';
                                if (text == _oldPassword.text) {
                                  return '新密码不能与当前密码相同';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _confirmPassword,
                              enabled: !_busy,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: const InputDecoration(
                                labelText: '确认新密码',
                                prefixIcon: BrandIcon(BIcons.check),
                              ),
                              validator: (value) =>
                                  value != _newPassword.text
                                  ? '两次输入的新密码不一致'
                                  : null,
                            ),
                          ],
                        ),
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
                      if (_success != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            _success!,
                            style: const TextStyle(color: AppColors.emerald),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: BrandButton(
                          onPressed: _busy ? null : _submit,
                          label: _busy ? '提交中…' : '更新密码',
                          icon: BIcons.lock,
                        ),
                      ),
                      const SizedBox(height: 34),
                      const Divider(),
                      const SizedBox(height: 18),
                      _heading('联系方式'),
                      const SizedBox(height: 4),
                      Text(
                        '绑定邮箱或手机后，忘记密码时可以自助找回。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      if (_loadingContact)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: BrandSpinner(size: 22)),
                        )
                      else ...[
                        _contactTile(
                          channel: 'email',
                          label: '邮箱',
                          value: _contact['email']?.toString() ?? '',
                          verified: _contact['email_verified'] == true,
                          hint: 'you@example.com',
                          icon: BIcons.mail,
                        ),
                        _contactTile(
                          channel: 'phone',
                          label: '手机号',
                          value: _contact['phone']?.toString() ?? '',
                          verified: _contact['phone_verified'] == true,
                          hint: '11 位手机号',
                          icon: BIcons.message,
                        ),
                      ],
                      const SizedBox(height: 34),
                      const Divider(),
                      const SizedBox(height: 18),
                      _heading('注销账号'),
                      const SizedBox(height: 4),
                      Text(
                        '注销后账号不可恢复，已发布内容会保留，作者显示为「已注销用户」。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _confirmDeleteAccount,
                          icon: const BrandIcon(BIcons.trash, size: 18),
                          label: const Text('永久注销账号'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 34),
                      const Divider(),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(child: _heading('登录设备')),
                          IconButton(
                            tooltip: '刷新',
                            onPressed: _loadingSessions
                                ? null
                                : () {
                                    setState(() => _loadingSessions = true);
                                    _loadSessions();
                                  },
                            icon: const BrandIcon(BIcons.refresh, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '发现不认识的设备，立即让它下线。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      if (_loadingSessions)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: BrandSpinner(size: 22)),
                        )
                      else if (_sessions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            '暂无登录设备记录。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      else
                        ..._sessions.map(_sessionTile),
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

  Widget _sessionTile(Map<String, dynamic> session) {
    final id = session['id']?.toString() ?? '';
    final current = session['current'] == true;
    final agent = _describeAgent(session['user_agent']?.toString() ?? '');
    final ip = session['ip']?.toString() ?? '';
    final createdAt = _formatTime(session['created_at']?.toString() ?? '');
    final revoking = _revokingId == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkBorder
              : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          const BrandIcon(BIcons.user, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        agent,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (current) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.emerald.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Text(
                          '当前设备',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.emerald,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${ip.isEmpty ? '未知 IP' : ip} · 登录于 $createdAt',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!current)
            TextButton(
              onPressed: revoking ? null : () => _revoke(session),
              child: Text(revoking ? '处理中…' : '下线'),
            ),
        ],
      ),
    );
  }

  Widget _heading(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);

  /// 邮箱 / 手机绑定行：未绑定时给「绑定」入口，已绑定时给「解绑」。
  Widget _contactTile({
    required String channel,
    required String label,
    required String value,
    required bool verified,
    required String hint,
    required BrandIconData icon,
  }) {
    final bound = value.isNotEmpty;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final badgeColor = !bound
        ? (dark ? AppColors.darkBorder : AppColors.lightBorder)
        : (verified ? AppColors.emerald : AppColors.gold);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          BrandIcon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        bound ? (verified ? '已验证' : '未验证') : '未绑定',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  bound ? value : '未绑定，可用于找回密码',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: bound
                ? () => _openUnbindDialog(channel: channel, label: label)
                : () => _openBindDialog(
                    channel: channel,
                    label: label,
                    hint: hint,
                  ),
            child: Text(bound ? '解绑' : '绑定'),
          ),
        ],
      ),
    );
  }

  String _describeAgent(String userAgent) {
    if (userAgent.isEmpty) return '未知设备';
    final browser = userAgent.contains('Edg/')
        ? 'Edge'
        : userAgent.contains('Chrome/')
        ? 'Chrome'
        : userAgent.contains('Firefox/')
        ? 'Firefox'
        : userAgent.contains('Safari/')
        ? 'Safari'
        : '浏览器';
    final os = userAgent.contains('Windows')
        ? 'Windows'
        : userAgent.contains('Android')
        ? 'Android'
        : (userAgent.contains('iPhone') || userAgent.contains('iPad'))
        ? 'iOS'
        : userAgent.contains('Mac OS X')
        ? 'macOS'
        : userAgent.contains('Linux')
        ? 'Linux'
        : '';
    return os.isEmpty ? browser : '$browser · $os';
  }

  String _formatTime(String raw) {
    final time = DateTime.tryParse(raw)?.toLocal();
    if (time == null) return raw.isEmpty ? '—' : raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// 绑定邮箱 / 手机的弹窗：输入联系方式 → 获取验证码 → 提交。
class _BindContactDialog extends StatefulWidget {
  const _BindContactDialog({
    required this.channel,
    required this.label,
    required this.hint,
  });

  final String channel;
  final String label;
  final String hint;

  @override
  State<_BindContactDialog> createState() => _BindContactDialogState();
}

class _BindContactDialogState extends State<_BindContactDialog> {
  final _target = TextEditingController();
  final _code = TextEditingController();
  Timer? _timer;
  int _countdown = 0;
  bool _sending = false;
  bool _submitting = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _timer?.cancel();
    _target.dispose();
    _code.dispose();
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
      setState(() => _error = '请输入${widget.label}');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _info = null;
    });
    var devCode = '';
    final error = await context.read<AppStateProvider>().sendCode(
      channel: widget.channel,
      target: target,
      purpose: 'bind',
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
    if (_submitting) return;
    final target = _target.text.trim();
    final code = _code.text.trim();
    if (target.isEmpty) {
      setState(() => _error = '请输入${widget.label}');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = '请输入 6 位数字验证码');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await context.read<AppStateProvider>().bindContact(
      channel: widget.channel,
      target: target,
      code: code,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text('绑定${widget.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _target,
            keyboardType: widget.channel == 'email'
                ? TextInputType.emailAddress
                : TextInputType.phone,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              prefixIcon: BrandIcon(
                widget.channel == 'email' ? BIcons.mail : BIcons.message,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '验证码'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _sending || _countdown > 0 ? null : _send,
                child: Text(
                  _countdown > 0
                      ? '${_countdown}s'
                      : _sending
                      ? '发送中…'
                      : '获取验证码',
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: TextStyle(color: errorColor)),
            ),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _info!,
                style: const TextStyle(color: AppColors.emerald),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? '绑定中…' : '绑定'),
        ),
      ],
    );
  }
}
