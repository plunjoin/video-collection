# PlayerScreen 一起看集成说明

## 集成步骤

### 1. 在PlayerScreen的State类中混入WatchTogetherMixin

```dart
import '../mixins/watch_together_mixin.dart';

class _PlayerScreenState extends State<PlayerScreen> with WatchTogetherMixin {
  // 现有代码...
  
  // 实现WatchTogetherMixin需要的getter
  @override
  Player get player => _player;
  
  @override
  Duration get position => _position;
  
  @override
  bool get isPlaying => _isPlaying;
  
  @override
  double get currentSpeed => _currentSpeed;
  
  @override
  int get currentGroupIndex => _currentGroupIndex;
  
  @override
  int get currentEpisodeIndex => _currentEpisodeIndex;
  
  // 实现WatchTogetherMixin需要的方法
  @override
  void onSwitchEpisode(int groupIndex, int episodeIndex) {
    _switchEpisode(groupIndex, episodeIndex);
  }
  
  @override
  void onShowMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
```

### 2. 在initState中初始化

```dart
@override
void initState() {
  super.initState();
  
  // 现有初始化代码...
  
  // 初始化Watch Together
  initWatchTogether();
  
  // 从ApiService获取当前用户ID并设置
  // 假设有一个方法可以获取当前用户
  _loadCurrentUser();
}

Future<void> _loadCurrentUser() async {
  try {
    final response = await _api.userRequest('/api/me');
    final userData = response['data'] as Map<String, dynamic>;
    final userId = userData['id'] as int;
    WatchTogetherService().setCurrentUserId(userId);
  } catch (e) {
    // 用户未登录,一起看功能不可用
  }
}
```

### 3. 在dispose中清理

```dart
@override
void dispose() {
  // 清理Watch Together
  disposeWatchTogether();
  
  // 现有清理代码...
  
  super.dispose();
}
```

### 4. 修改播放控制方法,支持一起看

```dart
void _togglePlayPause() {
  // 如果在一起看中且不是房主,阻止操作
  if (shouldBlockLocalControl()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('只有房主可以控制播放')),
    );
    return;
  }
  
  // 如果是房主,通过Watch Together发送意图
  if (isInWatchTogether && isWatchTogetherHost) {
    if (_isPlaying) {
      watchTogetherPause();
    } else {
      watchTogetherPlay();
    }
  }
  
  // 原有逻辑
  if (_isPlaying) _recordHistory(countHit: false);
  _player.playOrPause();
  _resetHideControlsTimer();
}

void _seekBy(int seconds) {
  // 如果在一起看中且不是房主,阻止操作
  if (shouldBlockLocalControl()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('只有房主可以控制播放')),
    );
    return;
  }
  
  // 原有逻辑
  var target = _position + Duration(seconds: seconds);
  if (target < Duration.zero) target = Duration.zero;
  if (_duration > Duration.zero && target > _duration) target = _duration;
  
  // 如果是房主,通过Watch Together发送意图
  if (isInWatchTogether && isWatchTogetherHost) {
    watchTogetherSeek(target);
  }
  
  _player.seek(target);
  _showQuickSeekFeedback(seconds > 0 ? '+$seconds秒' : '$seconds秒');
  _resetHideControlsTimer();
}

void _switchEpisode(int groupIndex, int episodeIndex) {
  // 如果在一起看中且不是房主,阻止操作
  if (shouldBlockLocalControl()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('只有房主可以切换剧集')),
    );
    return;
  }
  
  // 如果是房主,通过Watch Together发送意图
  if (isInWatchTogether && isWatchTogetherHost) {
    watchTogetherSwitchEpisode(groupIndex, episodeIndex);
  }
  
  // 原有逻辑
  if (!_hasError && _duration > Duration.zero) {
    _recordHistory(countHit: false);
  }
  _resumePosition = null;
  setState(() {
    _position = Duration.zero;
    _duration = Duration.zero;
    _currentGroupIndex = groupIndex;
    _currentEpisodeIndex = episodeIndex;
    _showFullscreenDrawer = false;
    _showSpeedPanel = false;
  });
  _loadAndPlayCurrentEpisode();
  unawaited(_loadDanmaku());
}

// 修改播放速率
void _setSpeed(double speed) {
  // 如果在一起看中且不是房主,阻止操作
  if (shouldBlockLocalControl()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('只有房主可以调整速率')),
    );
    return;
  }
  
  // 如果是房主,通过Watch Together发送意图
  if (isInWatchTogether && isWatchTogetherHost) {
    watchTogetherSetRate(speed);
  }
  
  // 原有逻辑
  setState(() => _currentSpeed = speed);
  _player.setRate(speed);
}
```

### 5. 修改播放历史记录,一起看期间不记录

```dart
void _recordHistory({bool countHit = true}) {
  // 一起看期间不记录播放历史
  if (!shouldRecordHistory()) return;
  
  // 原有记录逻辑...
}
```

### 6. 在UI中添加一起看按钮和状态显示

在播放器控制栏或菜单中添加:

```dart
// 创建房间按钮
IconButton(
  icon: const Icon(Icons.people_outline),
  onPressed: () async {
    await createWatchRoom(widget.video.id);
    // 显示房间码对话框
    if (mounted && watchRoomInfo != null) {
      showDialog(
        context: context,
        builder: (context) => RoomCreatedDialog(room: watchRoomInfo!.room),
      );
    }
  },
  tooltip: '创建一起看',
)

// 加入房间按钮
IconButton(
  icon: const Icon(Icons.group_add),
  onPressed: () async {
    final roomInfo = await showDialog<RoomInfo>(
      context: context,
      builder: (context) => const JoinWatchRoomDialog(),
    );
    if (roomInfo != null && mounted) {
      await joinWatchRoom(roomInfo);
    }
  },
  tooltip: '加入一起看',
)

// 房间信息显示(在一起看中时)
if (isInWatchTogether && watchRoomInfo != null)
  WatchRoomInfoWidget(
    roomInfo: watchRoomInfo!,
    isHost: isWatchTogetherHost,
    onLeave: () async {
      await _leaveWatchTogether();
    },
  )
```

## 测试清单

### 创建和加入
- [ ] 从视频详情页创建房间
- [ ] 显示房间码对话框
- [ ] 第二个设备输入房间码加入
- [ ] 加入后能看到参与者列表

### 播放同步
- [ ] 房主播放,成员自动播放
- [ ] 房主暂停,成员自动暂停
- [ ] 房主快进/快退,成员自动跟随
- [ ] 房主切换剧集,成员自动切换

### 权限控制
- [ ] 成员点击播放按钮显示提示
- [ ] 成员无法拖动进度条
- [ ] 成员无法切换剧集
- [ ] 成员无法调整播放速率

### 时间同步
- [ ] 轻微偏差(<400ms)不校正
- [ ] 中等偏差(400ms-2s)软校正(调整播放速率)
- [ ] 严重偏差(>2s)硬校正(立即seek)

### 播放历史
- [ ] 一起看期间不写入user_history
- [ ] 离开房间后恢复正常记录

### 边界情况
- [ ] 房主断开30秒后权限转移
- [ ] 最后一人离开房间自动关闭
- [ ] 房间过期(4小时)后无法加入
- [ ] 房间满员(6人)无法加入

## 注意事项

1. **WebSocket连接**: 确保API_BASE_URL支持WebSocket升级,使用ws://或wss://
2. **Token认证**: WebSocket连接时需要通过query参数或header传递认证token
3. **用户ID**: 需要在登录后从/api/me获取当前用户ID
4. **播放URL**: 不依赖服务器广播,本地通过ClientPlaylistService解析
5. **UI锁定**: 成员模式下禁用所有播放控制按钮(播放/暂停/seek/速率/切集)
