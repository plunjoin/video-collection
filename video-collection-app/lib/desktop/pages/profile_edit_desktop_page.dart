import '../../shared/ui/kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../shared/providers/app_state_provider.dart';
import '../../shared/widgets/brand_controls.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/member_avatar.dart';
import '../../shared/theme/brand_icons.dart';

class ProfileEditDesktopPage extends StatefulWidget {
  const ProfileEditDesktopPage({super.key});

  @override
  State<ProfileEditDesktopPage> createState() => _ProfileEditDesktopPageState();
}

class _ProfileEditDesktopPageState extends State<ProfileEditDesktopPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _avatar;
  late final TextEditingController _bio;
  bool _busy = false;
  bool _uploadingAvatar = false;
  bool _loadingAvatars = false;
  int? _avatarBusyId;
  List<Map<String, dynamic>> _avatars = const [];
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
    _loadAvatars();
  }

  /// 拉取历史头像（最多 20 条，服务端超出后自动裁剪并删除源文件）。
  Future<void> _loadAvatars() async {
    setState(() => _loadingAvatars = true);
    final list = await context.read<AppStateProvider>().listAvatars();
    if (!mounted) return;
    setState(() {
      _avatars = list;
      _loadingAvatars = false;
    });
  }

  /// 把历史头像切回当前头像：服务端立即生效，无需再点保存。
  Future<void> _useAvatar(Map<String, dynamic> item) async {
    if (_avatarBusyId != null || item['current'] == true) return;
    final id = (item['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    setState(() {
      _avatarBusyId = id;
      _error = null;
    });
    final message = await context.read<AppStateProvider>().useAvatar(id);
    if (!mounted) return;
    final url = item['url']?.toString() ?? '';
    setState(() {
      _avatarBusyId = null;
      if (message == null && url.isNotEmpty) _avatar.text = url;
    });
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    await _loadAvatars();
  }

  /// 删除历史头像：服务端会一并清理源文件，不可恢复。
  Future<void> _deleteAvatar(Map<String, dynamic> item) async {
    if (_avatarBusyId != null) return;
    if (item['current'] == true) {
      setState(() => _error = '当前正在使用的头像不能删除，请先切换到其他头像');
      return;
    }
    final id = (item['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这个头像？'),
        content: const Text('删除后该头像的源文件会被一并清理，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _avatarBusyId = id;
      _error = null;
    });
    final message = await context.read<AppStateProvider>().deleteAvatar(id);
    if (!mounted) return;
    setState(() {
      _avatarBusyId = null;
      if (message == null) {
        _avatars = _avatars
            .where((entry) => (entry['id'] as num?)?.toInt() != id)
            .toList(growable: false);
      } else {
        _error = message;
      }
    });
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
    if (message == null) await _loadAvatars();
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
                            icon: const BrandIcon(BIcons.image),
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
                        if (_loadingAvatars || _avatars.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '历史头像',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              Text(
                                '点按切换 · 长按删除',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_loadingAvatars)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final item in _avatars)
                                  _AvatarHistoryTile(
                                    url: item['url']?.toString() ?? '',
                                    current: item['current'] == true,
                                    busy:
                                        _avatarBusyId ==
                                        (item['id'] as num?)?.toInt(),
                                    onTap: () => _useAvatar(item),
                                    onLongPress: () => _deleteAvatar(item),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 4),
                          Text(
                            '最多保留 20 张，超出后自动清理最旧的图片；删除会同时删掉源文件。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
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
                        const SizedBox(height: 24),
                        BrandGradientButton(
                          onPressed: _busy ? null : _save,
                          loading: _busy,
                          label: '保存修改',
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

/// 历史头像格子：当前头像用品牌色描边，点按切换，长按删除。
class _AvatarHistoryTile extends StatelessWidget {
  const _AvatarHistoryTile({
    required this.url,
    required this.current,
    required this.busy,
    required this.onTap,
    required this.onLongPress,
  });

  final String url;
  final bool current;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: current || busy ? null : onTap,
      onLongPress: current || busy ? null : onLongPress,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(
            opacity: busy ? 0.45 : 1,
            child: MemberAvatar(
              avatar: url,
              frame: current ? '#597BEA' : '#E0E7FF',
              size: 62,
            ),
          ),
          if (current)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const BrandIcon(
                  BIcons.check,
                  size: 9,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
