import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_together_service.dart';
import '../models/watch_together_model.dart';

/// 加入一起看房间对话框
class JoinWatchRoomDialog extends StatefulWidget {
  const JoinWatchRoomDialog({super.key});

  @override
  State<JoinWatchRoomDialog> createState() => _JoinWatchRoomDialogState();
}

class _JoinWatchRoomDialogState extends State<JoinWatchRoomDialog> {
  final _codeController = TextEditingController();
  final _service = WatchTogetherService();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = '请输入房间码');
      return;
    }

    if (code.length != 6) {
      setState(() => _error = '房间码应为6位');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. 根据短码获取房间信息
      final roomInfo = await _service.getRoomByCode(code);

      // 2. 加入房间
      await _service.joinRoom(roomInfo.room.id);

      if (mounted) {
        // 返回房间信息
        Navigator.of(context).pop(roomInfo);
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.people, color: Colors.purple),
          SizedBox(width: 8),
          Text('加入一起看'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '输入房间码加入好友的一起看房间',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: InputDecoration(
              labelText: '房间码',
              hintText: '6位房间码',
              prefixIcon: const Icon(Icons.qr_code),
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
              UpperCaseTextFormatter(),
            ],
            autofocus: true,
            enabled: !_loading,
            onSubmitted: (_) => _joinRoom(),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton.icon(
          onPressed: _loading ? null : _joinRoom,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login),
          label: const Text('加入'),
        ),
      ],
    );
  }
}

/// 大写转换
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// 显示房间信息和参与者列表
class WatchRoomInfoWidget extends StatelessWidget {
  final RoomInfo roomInfo;
  final bool isHost;
  final VoidCallback? onLeave;

  const WatchRoomInfoWidget({
    super.key,
    required this.roomInfo,
    required this.isHost,
    this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.people, color: Colors.purple, size: 20),
              const SizedBox(width: 8),
              const Text(
                '一起看房间',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  roomInfo.room.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: roomInfo.participants.map((p) {
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: p.isHost ? Colors.orange : Colors.blue,
                  child: Text(
                    p.nickname.isNotEmpty ? p.nickname[0] : p.username[0],
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                label: Text(
                  p.nickname.isNotEmpty ? p.nickname : p.username,
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: p.isHost
                    ? Colors.orange.withOpacity(0.2)
                    : Colors.blue.withOpacity(0.1),
              );
            }).toList(),
          ),
          if (onLeave != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLeave,
                icon: const Icon(Icons.exit_to_app, size: 16),
                label: const Text('离开房间'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 创建房间成功对话框(显示房间码)
class RoomCreatedDialog extends StatelessWidget {
  final WatchRoom room;

  const RoomCreatedDialog({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('房间创建成功'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('分享房间码邀请好友一起观看:'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple, width: 2),
            ),
            child: Text(
              room.code,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: Colors.purple,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '有效期至 ${_formatDateTime(room.expiresAt)}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: room.code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('房间码已复制')),
            );
          },
          child: const Text('复制房间码'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('开始观看'),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
