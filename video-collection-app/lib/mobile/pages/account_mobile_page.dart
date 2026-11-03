import '../../shared/ui/kit.dart';
import 'package:provider/provider.dart';

import '../../shared/providers/app_state_provider.dart';
import '../../shared/theme/brand_icons.dart';
import '../../shared/widgets/brand_controls.dart';
import '../../shared/widgets/brand_widgets.dart';
import './reset_password_mobile_page.dart';

class AccountMobilePage extends StatefulWidget {
  const AccountMobilePage({super.key});
  @override
  State<AccountMobilePage> createState() => _AccountMobilePageState();
}

class _AccountMobilePageState extends State<AccountMobilePage> {
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

  Future<void> _goToResetPassword() async {
    final reset = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const ResetPasswordMobilePage(),
      ),
    );
    if (reset == true && mounted) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已重置，请用新密码登录')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: BrandAppBar(
        title: Text(_register ? '免费注册' : '账号登录'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Center(child: BrandLogo(width: 150)),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        '在更多的故事里，遇见更好的你 · 账户中心',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Web 风格 登录/注册 Tab 胶囊容器
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkCard
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.line,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (!_register) return;
                                setState(() {
                                  _register = false;
                                  _error = null;
                                });
                              },
                              behavior: HitTestBehavior.opaque,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: !_register
                                      ? (isDark
                                          ? AppColors.darkBg
                                          : Colors.white)
                                      : Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  boxShadow: !_register
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '账号登录',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: !_register
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: !_register
                                          ? AppColors.brandSolid
                                          : (isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.muted),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (_register) return;
                                setState(() {
                                  _register = true;
                                  _error = null;
                                });
                              },
                              behavior: HitTestBehavior.opaque,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: _register
                                      ? (isDark
                                          ? AppColors.darkBg
                                          : Colors.white)
                                      : Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  boxShadow: _register
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '免费注册',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: _register
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: _register
                                          ? AppColors.brandSolid
                                          : (isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.muted),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 错误提示条
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: const Color(0xFFFECDD3)),
                        ),
                        child: Row(
                          children: [
                            const BrandIcon(
                              BIcons.alert,
                              size: 16,
                              color: Color(0xFFE11D48),
                              monochrome: true,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFE11D48),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 用户名
                    TextFormField(
                      controller: _username,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: '用户名 / 账号',
                        hintText: '请输入用户名',
                        suffixIcon: BrandIcon(
                          BIcons.user,
                          size: 16,
                          color: AppColors.muted,
                          monochrome: true,
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '请输入用户名' : null,
                    ),
                    const SizedBox(height: 16),

                    // 注册额外昵称
                    if (_register) ...[
                      TextFormField(
                        controller: _nickname,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: '昵称（选填）',
                          hintText: '给自己起一个喜欢的昵称',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 密码
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      autofillHints: [
                        _register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: const InputDecoration(
                        labelText: '密码',
                        hintText: '请输入密码',
                      ),
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => v == null || v.isEmpty
                          ? '请输入密码'
                          : _register && v.trim().length < 6
                              ? '密码至少 6 位'
                              : null,
                    ),
                    const SizedBox(height: 24),

                    // 品牌主色渐变提交按钮
                    BrandGradientButton(
                      onPressed: _busy ? null : _submit,
                      loading: _busy,
                      label: _register ? '立即注册并登录' : '立即登录',
                    ),
                    const SizedBox(height: 16),

                    // 忘记密码
                    if (!_register)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '忘记密码？ ',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.muted,
                            ),
                          ),
                          GestureDetector(
                            onTap: _busy ? null : _goToResetPassword,
                            behavior: HitTestBehavior.opaque,
                            child: const Text(
                              '用邮箱或手机号找回',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brandSolid,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
