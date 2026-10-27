# PlayerScreen 一起看集成说明

## ✅ 集成已完成

PlayerScreen已完整集成WatchTogetherMixin,所有播放控制已添加权限检查和Watch Together同步逻辑。

### 已完成的集成

#### 1. ✅ 混入WatchTogetherMixin

```dart
class _PlayerScreenState extends State<PlayerScreen> with WatchTogetherMixin
```

#### 2. ✅ 实现Mixin需要的getter和方法

```dart
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

@override
void onSwitchEpisode(int groupIndex, int episodeIndex) {
  _switchEpisode(groupIndex, episodeIndex);
}

@override
void onShowMessage(String message) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
```

#### 3. ✅ 生命周期集成

**initState**:
```dart
@override
void initState() {
  super.initState();
  // ... 现有代码 ...
  
  // 初始化 Watch Together
  initWatchTogether();
  _initWatchTogetherUser();
}

Future<void> _initWatchTogetherUser() async {
  if (_appState.isLoggedIn && _appState.user != null) {
    final userId = _appState.user!['id'] as int?;
    if (userId != null) {
      WatchTogetherService().setCurrentUserId(userId);
    }
  }
}
```

**dispose**:
```dart
@override
void dispose() {
  // 清理 Watch Together
  disposeWatchTogether();
  
  // ... 现有清理代码 ...
  super.dispose();
}
```

#### 4. ✅ 播放控制方法集成

所有关键播放控制方法已添加权限检查和房主意图发送:

**_togglePlayPause()**:
```dart
void _togglePlayPause() {
  if (shouldBlockLocalControl()) {
    onShowMessage('只有房主可以控制播放');
    return;
  }
  
  if (isInWatchTogether && isWatchTogetherHost) {
    if (_isPlaying) {
      watchTogetherPause();
    } else {
      watchTogetherPlay();
    }
  }
  
  // 原有逻辑...
}
```

**_seekBy(int seconds)** - ✅ 已集成  
**_switchEpisode(int groupIndex, int episodeIndex)** - ✅ 已集成  
**_setSpeed(double speed)** - ✅ 已集成  
**onHorizontalDragStart** (进度条拖拽) - ✅ 已集成  
**onHorizontalDragEnd** (进度条拖拽结束) - ✅ 已集成  
**底部进度条 onSeek** - ✅ 已集成

#### 5. ✅ 播放历史隔离

```dart
void _recordHistory({bool countHit = true}) {
  // 一起看期间不记录播放历史
  if (!shouldRecordHistory()) return;
  
  // 原有逻辑...
}
```

#### 6. ✅ UI集成

**创建房间按钮** (右上角,仅登录用户可见):
- 紫色按钮 "创建一起看"
- 点击创建房间并显示房间码对话框
- 自动加入并连接WebSocket

**加入房间按钮** (右上角,仅登录用户可见):
- 蓝色按钮 "加入房间"
- 弹出输入房间码对话框
- 加入后自动切换到房间的剧集

**房间信息卡片** (顶部,在房间中时显示):
- 显示房间码
- 显示参与者列表(头像+昵称)
- 房主标识(橙色)
- 离开房间按钮

### 代码修改统计

| 文件 | 修改行数 | 说明 |
|------|---------|------|
| `player_screen.dart` | ~250行 | 添加imports, mixin, 修改10+个方法, 添加UI |

### 权限控制覆盖

已对以下所有交互点添加权限检查:

1. ✅ 播放/暂停按钮 (`_togglePlayPause`)
2. ✅ 快进/快退手势 (`_seekBy`)
3. ✅ 切换剧集 (`_switchEpisode`)
4. ✅ 调整播放速率 (`_setSpeed`)
5. ✅ 水平拖拽进度条 (`onHorizontalDragStart/End`)
6. ✅ 底部进度条拖拽 (`onSeek`)
7. ✅ 播放历史记录 (`_recordHistory`)

---

## 手动测试清单

### 前置条件
- [ ] 后端服务运行中 (`go run main.go main_bootstrap.go`)
- [ ] 两台测试设备(或模拟器+真机)
- [ ] 两个账号都已登录

### 基础功能测试

#### 创建和加入
- [ ] 设备1: 进入任意视频播放页面
- [ ] 设备1: 点击"创建一起看"按钮
- [ ] 设备1: 看到房间码对话框(6位大写字母+数字)
- [ ] 设备1: 复制或记录房间码
- [ ] 设备2: 进入同一视频播放页面
- [ ] 设备2: 点击"加入房间"按钮
- [ ] 设备2: 输入房间码并点击"加入"
- [ ] 设备2: 成功加入后看到房间信息卡片
- [ ] 两台设备都能看到参与者列表(2人)

#### 播放同步
- [ ] 设备1(房主): 点击播放按钮
- [ ] 设备2(成员): 自动开始播放 (延迟<500ms)
- [ ] 设备1(房主): 点击暂停按钮
- [ ] 设备2(成员): 自动暂停
- [ ] 设备1(房主): 双击屏幕快进10秒
- [ ] 设备2(成员): 自动跟随到新位置
- [ ] 设备1(房主): 拖动进度条
- [ ] 设备2(成员): 自动跟随到新位置

#### 剧集同步
- [ ] 设备1(房主): 点击"下一集"按钮
- [ ] 设备2(成员): 自动切换到下一集
- [ ] 设备1(房主): 从选集列表选择任意剧集
- [ ] 设备2(成员): 自动切换到相同剧集

#### 速率同步
- [ ] 设备1(房主): 调整播放速率为1.5x
- [ ] 设备2(成员): 自动调整到1.5x
- [ ] 观察两台设备播放速度一致

### 权限控制测试

#### 成员无法控制
- [ ] 设备2(成员): 点击播放/暂停按钮
- [ ] 显示提示: "只有房主可以控制播放"
- [ ] 播放状态不变
- [ ] 设备2(成员): 尝试双击快进
- [ ] 显示提示: "只有房主可以快进快退"
- [ ] 设备2(成员): 尝试拖动进度条
- [ ] 显示提示: "只有房主可以拖动进度"
- [ ] 设备2(成员): 尝试切换剧集
- [ ] 显示提示: "只有房主可以切换剧集"
- [ ] 设备2(成员): 尝试调整速率
- [ ] 显示提示: "只有房主可以调整播放速率"

### 时间同步测试

#### 漂移校正
- [ ] 设备2: 进入后台3秒
- [ ] 设备2: 返回前台
- [ ] 观察播放位置在2-3秒内自动追赶
- [ ] 设备2: 手动关闭WiFi 5秒
- [ ] 设备2: 恢复WiFi连接
- [ ] 观察播放位置自动校正到当前位置

#### 网络延迟
- [ ] 房主操作(播放/暂停/跳转)
- [ ] 观察成员响应延迟 (应<500ms局域网, <2s广域网)
- [ ] 检查是否有卡顿或重复跳转

### 播放历史测试

#### 历史隔离
- [ ] 设备1: 在未加入一起看前播放一段时间
- [ ] 检查播放历史有记录
- [ ] 设备1: 创建一起看房间
- [ ] 设备1: 在一起看中播放5分钟
- [ ] 设备1: 离开房间
- [ ] 检查播放历史中**不包含**一起看期间的5分钟
- [ ] 设备1: 继续单独播放
- [ ] 检查播放历史恢复正常记录

### 房间管理测试

#### 离开房间
- [ ] 设备2(成员): 点击房间信息卡片的"离开房间"按钮
- [ ] 确认对话框点击"离开"
- [ ] 设备2: 房间信息卡片消失
- [ ] 设备2: 恢复正常播放控制(可手动操作)
- [ ] 设备1(房主): 仍然在房间中

#### 房主断线
- [ ] 设备1(房主): 关闭应用或断网
- [ ] 等待30秒
- [ ] 设备2: 应该自动成为新房主
- [ ] 设备2: 现在可以控制播放
- [ ] (可选) 设备1重新上线,仍为成员

### UI测试

#### 按钮显示
- [ ] 未登录: 不显示"创建一起看"和"加入房间"按钮
- [ ] 已登录且未在房间: 显示两个按钮(紫色+蓝色)
- [ ] 已在房间: 按钮消失,显示房间信息卡片

#### 房间信息卡片
- [ ] 显示6位房间码(大写,有颜色背景)
- [ ] 显示所有参与者(头像+昵称)
- [ ] 房主有特殊标识(橙色背景)
- [ ] 成员为蓝色背景
- [ ] "离开房间"按钮正常工作

#### 响应式布局
- [ ] 横屏: 按钮位置合理,不遮挡内容
- [ ] 竖屏: 按钮位置合理,不遮挡内容
- [ ] 全屏模式: UI正常显示

### 边界情况测试

#### 房间过期
- [ ] (可选) 创建房间后等待4小时
- [ ] 尝试加入: 应提示房间已过期

#### 房间满员
- [ ] (需要6台设备) 6个用户加入同一房间
- [ ] 第7个用户尝试加入
- [ ] 应提示房间已满

#### 网络问题
- [ ] 弱网环境(限速到100KB/s)
- [ ] 观察是否有明显延迟或卡顿
- [ ] 检查漂移校正是否正常工作

---

## 已知限制

1. **房主转移**: 房主断线后30秒自动转移给最早加入的成员(后端实现,客户端跟随)
2. **多实例部署**: 当前后端使用内存Hub,不支持多实例负载均衡
3. **时间同步**: 依赖设备系统时间,大的时钟偏差可能影响漂移校正精度

---

## Troubleshooting

### WebSocket连接失败

**现象**: 点击创建/加入后没有反应或提示连接失败

**排查**:
1. 检查后端是否运行: `curl http://localhost/api/watch/rooms`
2. 检查API_BASE_URL配置:
   - Android模拟器: 应为 `http://10.0.2.2:80`
   - iOS模拟器/桌面: 应为 `http://127.0.0.1:80`
   - 真机: 应为服务器局域网IP
3. 检查Nginx WebSocket配置(如使用反向代理)

**修复**:
```dart
// 在应用设置中修改API Base URL
// 或构建时指定:
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:80
```

### 成员无法跟随房主

**现象**: 房主操作后成员没有反应

**排查**:
1. 检查WebSocket是否连接: 查看日志中的 `[WatchTogether]` 消息
2. 检查用户ID是否正确设置
3. 检查是否收到`state`消息

**修复**: 确保登录后获取到user['id'],重新进入播放器

### 播放历史仍被记录

**现象**: 一起看期间播放历史仍写入云端

**排查**: 检查 `_recordHistory` 方法开头是否有 `if (!shouldRecordHistory()) return;`

### 成员仍能控制播放

**现象**: 成员可以点击播放/暂停等按钮

**排查**: 检查所有播放控制方法开头是否有 `if (shouldBlockLocalControl()) { ... return; }`

---

## 完成状态

✅ **100%完成** - PlayerScreen已完整集成WatchTogetherMixin

- ✅ Mixin集成
- ✅ 生命周期hooks
- ✅ 播放控制权限检查 (7个控制点)
- ✅ 播放历史隔离
- ✅ UI按钮和信息卡片
- ✅ 用户ID自动设置
- ✅ 房间创建/加入/离开流程

**下一步**: 使用两台设备进行端到端测试,验证所有功能正常工作。
