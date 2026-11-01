import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../widgets/brand_controls.dart';
import '../widgets/member_avatar.dart';
import '../theme/brand_icons.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _avatar;
  late final TextEditingController _bio;
  bool _busy = false;
  bool _uploadingAvatar = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppStateProvider>().user;
    _nickname = TextEditingController(
      text: user?['nickname']?.toString() ?? '',
    );
    _avatar = TextEditingController(
      text: user?['profile_avatar']?.toString().isNotEmpty == true
          ? user!['profile_avatar'].toString()
          : user?['avatar']?.toString() ?? '',
    );
    _bio = TextEditingController(text: user?['bio']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nickname.dispose();
    _avatar.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await context.read<AppStateProvider>().updateProfile(
      nickname: _nickname.text,
      avatar: _avatar.text,
      bio: _bio.text,
    );
    if (!mounted) return;
    if (message == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  /// 从相册选图并上传，成功后把返回的相对路径回填到头像输入框。
  Future<void> _pickAvatar() async {
    if (_busy || _uploadingAvatar) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 2 * 1024 * 1024) {
      setState(() => _error = '图片不能超过 2MB');
      return;
    }
    setState(() {
      _uploadingAvatar = true;
      _error = null;
    });
    final name = picked.name.isEmpty ? 'avatar.jpg' : picked.name;
    final message = await context.read<AppStateProvider>().uploadAvatar(
      bytes: bytes,
      filename: name,
    );
    if (!mounted) return;
    final uploaded =
        context.read<AppStateProvider>().user?['profile_avatar']?.toString() ??
        '';
    setState(() {
      _uploadingAvatar = false;
      _error = message;
      if (message == null && uploaded.isNotEmpty) _avatar.text = uploaded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppStateProvider>().user;
    final username = user?['username']?.toString() ?? '';
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Scaffold(
              appBar: const BrandAppBar(title: Text('编辑资料')),
              body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Center(
                          child: MemberAvatar(
                            avatar: _avatar.text.trim(),
                            frame:
                                user?['decorations']?['frame']?.toString() ??
                                '',
                            size: 84,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: TextButton.icon(
                            onPressed: _busy || _uploadingAvatar
                                ? null
                                : _pickAvatar,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(
                              _uploadingAvatar ? '上传中…' : '从相册上传头像',
                            ),
                          ),
                        ),
                        Center(
                          child: Text(
                            username.isEmpty ? '未登录' : '@$username',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _nickname,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: '昵称',
                            prefixIcon: BrandIcon(BIcons.badge),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty || text.runes.length > 20) {
                              return '昵称需要 1 到 20 个字';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _bio,
                          enabled: !_busy,
                          maxLength: 80,
                          minLines: 2,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: '个人简介',
                            alignLabelWithHint: true,
                            prefixIcon: BrandIcon(BIcons.notes),
                          ),
                          validator: (value) =>
                              (value?.trim().runes.length ?? 0) > 80
                              ? '简介最多 80 个字'
                              : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _avatar,
                          enabled: !_busy,
                          keyboardType: TextInputType.url,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: '头像链接',
                            hintText: 'https:// 开头，留空则使用默认头像',
                            prefixIcon: BrandIcon(BIcons.image),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return null;
                            final uri = Uri.tryParse(text);
                            final remote =
                                uri != null &&
                                (uri.scheme == 'http' ||
                                    uri.scheme == 'https') &&
                                uri.host.isNotEmpty;
                            final local =
                                text.startsWith('/') && !text.contains('..');
                            if (!remote && !local) return '请填写 http 或 https 链接';
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text('用户名不能在这里修改。已佩戴的装扮头像会优先显示在个人主页。'),
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
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          child: Text(_busy ? '保存中…' : '保存'),
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
