import '../ui/kit.dart';
import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

import '../services/watch_together_service.dart';
import '../theme/app_colors.dart';
import '../theme/brand_icons.dart';

/// 一起看房间面板：建房 / 房间码加入 / 成员 / 房间聊天。
///
/// 嵌在播放页下半屏的「一起看」标签页里，跟随浅色 / 深色主题。
/// 房间态采用压缩布局：单行头部 + 聊天（成员行随列表滚动）+ 输入框，
/// 固定高度约 100px，桌面端小窗口下也能完整看到输入框。
class WatchTogetherPanel extends StatefulWidget {
  final WatchTogether watch;
  final bool isDark;
  final bool loggedIn;
  final int videoId;
  final int Function() currentGroupIndex;
  final int Function() currentEpisodeIndex;
  final String videoName;
  final String Function() currentEpisodeName;

  const WatchTogetherPanel({
    super.key,
    required this.watch,
    required this.isDark,
    required this.loggedIn,
    required this.videoId,
    required this.currentGroupIndex,
    required this.currentEpisodeIndex,
    required this.videoName,
    required this.currentEpisodeName,
  });

  @override
  State<WatchTogetherPanel> createState() => _WatchTogetherPanelState();
}

class _WatchTogetherPanelState extends State<WatchTogetherPanel> {
  final _codeController = TextEditingController();
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  bool _busy = false;
  bool _sending = false;
  bool _allowAllControl = false;

  @override
  void initState() {
    super.initState();
    widget.watch.addListener(_onWatchChanged);
  }

  @override
  void dispose() {
    widget.watch.removeListener(_onWatchChanged);
    _codeController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _onWatchChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.watch.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.jumpTo(
            _chatScrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  Color get _ink => widget.isDark
      ? AppColors.darkTextPrimary
      : AppColors.lightTextPrimary;
  Color get _muted => widget.isDark
      ? AppColors.darkTextSecondary
      : AppColors.lightTextSecondary;
  Color get _card => widget.isDark ? AppColors.darkCard : AppColors.lightCard;
  Color get _border => widget.isDark
      ? AppColors.darkBorder
      : AppColors.lightBorder;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _createRoom() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await widget.watch.create(
      videoId: widget.videoId,
      groupIndex: widget.currentGroupIndex(),
      episodeIndex: widget.currentEpisodeIndex(),
      controlMode: _allowAllControl ? 'all' : 'host',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _toast(error);
    } else {
      _toast('房间已创建，把房间码分享给朋友吧');
    }
  }

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (_busy || code.length != 6) {
      _toast('请输入 6 位房间码');
      return;
    }
    setState(() => _busy = true);
    final error = await widget.watch.join(code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _toast(error);
    } else {
      _codeController.clear();
      _toast('已加入房间');
    }
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (_sending || text.isEmpty) return;
    setState(() => _sending = true);
    _chatController.clear();
    final error = await widget.watch.sendChat(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) _toast(error);
  }

  Future<void> _leaveRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出一起看'),
        content: const Text('退出后将不再跟随房主同步，确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.watch.leave();
    }
  }

  Future<void> _transferHost(WatchMemberView member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('把房主转让给 ${member.nickname}？'),
        content: const Text('转让后由对方控制播放进度与选集。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('转让'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await widget.watch.transferHost(member.userId);
    if (error != null) _toast(error);
  }

  Future<void> _toggleControlMode(String currentMode) async {
    if (!widget.watch.isHost) return;
    final next = currentMode == 'all' ? 'host' : 'all';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(next == 'all' ? '开放播放控制？' : '收回播放控制？'),
        content: Text(
          next == 'all'
              ? '房间里的所有成员都能播放、暂停、拖进度和切集。'
              : '控制权收回后，播放只由房主操作。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await widget.watch.setControlMode(next);
    if (error != null) _toast(error);
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    _toast('房间码 $code 已复制');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.loggedIn) {
      return _hintBlock(
        BIcons.login,
        '登录后就能和朋友一起看',
        '一起看需要登录账号，登录后在这里创建房间，或用房间码加入朋友的房间。',
      );
    }
    final watch = widget.watch;
    if (!watch.active) {
      return _buildLobby();
    }
    return _buildRoom(watch);
  }

  Widget _hintBlock(BrandIconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandIcon(icon, size: 40, color: _muted),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobby() {
    final snap = widget.watch.snapshot;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        Row(
          children: [
            BrandIcon(BIcons.live, size: 20, color: AppColors.primary600),
            const SizedBox(width: 8),
            Text(
              '和朋友同步看，进度永远一致',
              style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '房主控制播放、拖进度、切集，所有人自动跟随；房间里的消息只有成员可见。',
          style: TextStyle(fontSize: 13, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 14),
        // 建房时选择控制权限
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '允许所有人控制播放',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '关闭时只有你能操作播放；开启后所有成员都可以播放、暂停、拖进度和切集。',
                      style: TextStyle(fontSize: 12, color: _muted, height: 1.4),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _allowAllControl,
                activeThumbColor: AppColors.primary600,
                onChanged: (value) => setState(() => _allowAllControl = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _busy ? null : _createRoom,
          icon: const BrandIcon(BIcons.playCircle, size: 18),
          label: Text(
            _busy ? '创建中…' : '为当前影片创建房间',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${widget.videoName} · ${widget.currentEpisodeName()}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('已有房间？', style: TextStyle(fontSize: 12, color: _muted)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                autocorrect: false,
                style: TextStyle(
                  letterSpacing: 6,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: _ink,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '房间码',
                  hintStyle: TextStyle(
                    letterSpacing: 2,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                  filled: true,
                  fillColor: _card,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary600),
                  ),
                ),
                onSubmitted: (_) => _joinRoom(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _busy ? null : _joinRoom,
              child: const Text('加入', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        if (snap != null && !snap.viewerIsHost)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '成员发送的聊天会以「昵称：内容」的形式出现在弹幕里',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _muted),
            ),
          ),
      ],
    );
  }

  Widget _buildRoom(WatchTogether watch) {
    return Column(
      children: [
        _roomHeader(watch),
        Expanded(child: _chatList()),
        _chatInput(),
      ],
    );
  }

  Widget _roomHeader(WatchTogether watch) {
    final snap = watch.snapshot!;
    final controlLabel = snap.controlMode == 'all' ? '所有人可控制' : '仅房主控制';
    final statusLine = watch.isHost
        ? (snap.controlMode == 'all' ? '你是房主 · 所有人可控制' : '你是房主，大家跟着你走')
        : (snap.controlMode == 'all' ? '所有人可控制播放' : '房主控制播放中');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          BrandIcon(BIcons.live, size: 15, color: AppColors.rose),
          const SizedBox(width: 6),
          // 控制权限 chip：房主可点击切换
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap:
                watch.isHost ? () => _toggleControlMode(snap.controlMode) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: snap.controlMode == 'all'
                    ? AppColors.emerald.withValues(alpha: 0.12)
                    : AppColors.primary500.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controlLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: snap.controlMode == 'all'
                          ? AppColors.emerald
                          : AppColors.primary600,
                    ),
                  ),
                  if (watch.isHost) ...[
                    const SizedBox(width: 3),
                    BrandIcon(
                      BIcons.refresh,
                      size: 10,
                      color: snap.controlMode == 'all'
                          ? AppColors.emerald
                          : AppColors.primary600,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snap.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: _ink,
                  ),
                ),
                Text(
                  statusLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 房间码 + 复制
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _copyCode(snap.code),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snap.code,
                    style: const TextStyle(
                      letterSpacing: 2,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const BrandIcon(BIcons.share, size: 12, color: Colors.white),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '退出房间',
                  onPressed: _leaveRoom,
            icon: BrandIcon(BIcons.logout, size: 17, color: _muted),
          ),
        ],
      ),
    );
  }

  /// 成员行（放在聊天列表首项，空间紧张时随列表滚动）。
  Widget _memberRow(WatchRoomSnapshot snap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final member in snap.members)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap:
                  widget.watch.isHost && !member.isHost
                      ? () => _transferHost(member)
                      : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (member.isHost)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '房主',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      CircleAvatar(
                        radius: 9,
                        backgroundColor: AppColors.primary100,
                        backgroundImage:
                            member.avatar.isNotEmpty &&
                                member.avatar.startsWith('http')
                            ? NetworkImage(member.avatar)
                            : null,
                        child:
                            member.avatar.isEmpty ||
                                !member.avatar.startsWith('http')
                            ? Text(
                                member.nickname.isNotEmpty
                                    ? member.nickname.characters.first
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.primary700,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                    const SizedBox(width: 5),
                    Text(
                      member.nickname,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: member.isHost
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: member.isHost ? _ink : _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chatList() {
    final messages = widget.watch.messages;
    final snap = widget.watch.snapshot;
    return ListView.builder(
      controller: _chatScrollController,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          if (snap == null) return const SizedBox.shrink();
          return _memberRow(snap);
        }
        final msg = messages[index - 1];
        final fromHost = msg.userId == snap?.hostId;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (fromHost) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '房主',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      msg.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fromHost ? AppColors.primary600 : _muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  msg.content,
                  style: TextStyle(fontSize: 14, color: _ink, height: 1.4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chatInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              maxLength: 100,
              style: TextStyle(fontSize: 14, color: _ink),
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                hintText: '和房间里的人聊聊…',
                hintStyle: TextStyle(fontSize: 13, color: _muted),
                filled: true,
                fillColor: widget.isDark ? AppColors.darkBg : AppColors.lightBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary600),
                ),
              ),
              onSubmitted: (_) => _sendChat(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary600,
              minimumSize: const Size(38, 38),
            ),
            onPressed: _sending ? null : _sendChat,
            icon: const BrandIcon(BIcons.send, size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
