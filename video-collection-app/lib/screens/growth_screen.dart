import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../widgets/member_avatar.dart';

class GrowthScreen extends StatefulWidget {
  const GrowthScreen({super.key});
  @override
  State<GrowthScreen> createState() => _GrowthScreenState();
}

class _GrowthScreenState extends State<GrowthScreen> {
  final _title = TextEditingController(), _details = TextEditingController();
  Map<String, dynamic> _wallet = {};
  Map<String, dynamic> _journey = {};
  List<dynamic> _wall = [];
  int _wallPage = 1, _wallTotal = 0;
  List<dynamic> _shop = [], _requests = [], _notifications = [];
  bool _loading = true, _busy = false;
  String? _error;
  int _requestPage = 1, _requestTotal = 0, _inboxPage = 1, _inboxTotal = 0;
  final _kinds = const {
    'avatar': '头像',
    'animated_avatar': '动态头像',
    'frame': '头像框',
    'badge': '铭牌',
    'nickname_color': '彩色昵称',
  };
  final _states = const {
    'pending': '待处理',
    'processing': '寻找中',
    'fulfilled': '已完成',
    'rejected': '未采纳 / 已退款',
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.userRequest('/api/user/points'),
        api.userRequest('/api/user/shop'),
        api.userRequest('/api/user/movie-requests?page=$_requestPage'),
        api.userRequest('/api/user/notifications?page=$_inboxPage'),
        api.userRequest('/api/user/journey'),
        api.userRequest('/api/movie-request-wall?page=$_wallPage'),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = Map<String, dynamic>.from(results[0]['data']);
        _shop = results[1]['data'];
        _requests = results[2]['data'];
        _requestTotal = results[2]['total'];
        _notifications = results[3]['data'];
        _inboxTotal = results[3]['total'];
        _journey = Map<String, dynamic>.from(results[4]['data']);
        _wall = results[5]['data'];
        _wallTotal = results[5]['total'];
        _loading = false;
        _error = null;
      });
      await context.read<AppStateProvider>().refreshProfile();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _action(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('积分消费确认'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
  Widget _card(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
  Widget _pager(int page, int total, void Function(int) change) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        onPressed: page > 1 && !_busy ? () => change(page - 1) : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Text('$page / ${((total + 19) ~/ 20).clamp(1, 1000000)}'),
      IconButton(
        onPressed: page * 20 < total && !_busy ? () => change(page + 1) : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('同好成长站'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: '成长日常'),
            Tab(text: '装扮商店'),
            Tab(text: '积分求片'),
            Tab(text: '同好心愿'),
            Tab(text: '消息通知'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : AbsorbPointer(
              absorbing: _busy,
              child: TabBarView(
                children: [
                  _rewards(),
                  _store(),
                  _movieRequests(),
                  _wishWall(),
                  _inbox(),
                ],
              ),
            ),
    ),
  );
  Widget _rewards() {
    final user = context.watch<AppStateProvider>().user ?? {},
        d = user['decorations'] as Map? ?? {},
        rules = _wallet['rules'] as Map? ?? {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card([
          Row(
            children: [
              MemberAvatar(
                avatar: user['avatar']?.toString() ?? '',
                frame: d['frame']?.toString() ?? '',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['nickname']?.toString() ??
                          user['username']?.toString() ??
                          '',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: memberColor(d['nickname_color']),
                      ),
                    ),
                    if (d['badge']?.toString().isNotEmpty == true)
                      Chip(label: Text(d['badge'].toString())),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '${_wallet['balance'] ?? 0} 积分',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          ),
          Text('连续签到 ${_wallet['streak'] ?? 0} 天 · 按北京时间每日重置'),
          const SizedBox(height: 12),
          Text(
            'Lv.${_journey['level']?['level'] ?? 1} · ${_journey['level']?['name'] ?? ''}',
          ),
          Text('${_journey['experience'] ?? 0} 成长值 · 兑换不降级，退款不重复计入成长'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _wallet['checked_in'] == true
                ? null
                : () => _action(() async {
                    final r = await ApiService().userRequest(
                      '/api/user/points/checkin',
                      method: 'POST',
                      body: {},
                    );
                    return '签到奖励 +${r['data']['earned']} 积分';
                  }),
            child: Text(_wallet['checked_in'] == true ? '今日已签到' : '签到领积分'),
          ),
          const SizedBox(height: 12),
          Text(
            '每日活跃 +${rules['active']}，签到 +${rules['checkin']} 起；连续签到每天多 ${rules['streak_step']}，单日最多 ${rules['streak_cap']} 积分。',
          ),
        ]),
        _card([
          const Text(
            '日常里的小小成就',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          for (final m in _journey['missions'] as List? ?? [])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                m['name'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m['description'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${m['period'] == 'day' ? '每日' : '成就'} · ${m['progress']}/${m['target']} · +${m['reward']} 积分',
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: TextButton(
                onPressed: m['claimed'] == true || m['progress'] < m['target']
                    ? null
                    : () => _action(() async {
                        final r = await ApiService().userRequest(
                          '/api/user/missions/claim',
                          method: 'POST',
                          body: {'key': m['key']},
                        );
                        return '收下 ${r['data']['earned']} 积分';
                      }),
                child: Text(
                  m['claimed'] == true
                      ? '已收下'
                      : m['progress'] >= m['target']
                      ? '领取'
                      : '进行中',
                ),
              ),
            ),
        ]),
        _card([
          const Text(
            '最近100笔积分流水',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          for (final e in _wallet['ledger'] as List? ?? [])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e['reason']),
              subtitle: Text('${e['created_at']} · 余额 ${e['balance']}'),
              trailing: Text('${e['amount'] >= 0 ? '+' : ''}${e['amount']}'),
            ),
        ]),
      ],
    );
  }

  Widget _store() => LayoutBuilder(
    builder: (context, box) => GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: box.maxWidth > 900
            ? 4
            : box.maxWidth > 560
            ? 3
            : 2,
        mainAxisExtent: 285,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _shop.length,
      itemBuilder: (context, i) {
        final c = _shop[i],
            kind = c['kind'].toString(),
            owned = c['owned'] == true,
            equipped = c['equipped'] == true;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (kind == 'avatar' || kind == 'animated_avatar')
                  MemberAvatar(avatar: c['value'], size: 72)
                else if (kind == 'frame')
                  MemberAvatar(frame: c['value'], size: 72)
                else
                  Text(
                    kind == 'badge' ? c['value'] : '彩色昵称',
                    style: TextStyle(
                      fontSize: 20,
                      color: kind == 'nickname_color'
                          ? memberColor(c['value'])
                          : null,
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  c['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(_kinds[kind] ?? kind),
                Text(owned ? '已拥有' : '${c['price']} 积分'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _action(() async {
                    if (!owned) {
                      if (!await _confirm(
                        '使用 ${c['price']} 积分兑换「${c['name']}」？',
                      )) {
                        return '已取消兑换';
                      }
                      await ApiService().userRequest(
                        '/api/user/shop/redeem',
                        method: 'POST',
                        body: {'id': c['id']},
                      );
                      return '兑换成功，可立即佩戴';
                    }
                    await ApiService().userRequest(
                      '/api/user/shop/equip',
                      method: 'POST',
                      body: {
                        'id': equipped ? 0 : c['id'],
                        'slot': kind == 'animated_avatar' ? 'avatar' : kind,
                      },
                    );
                    return equipped ? '装扮已卸下' : '装扮已佩戴';
                  }),
                  child: Text(
                    equipped
                        ? '卸下'
                        : owned
                        ? '佩戴'
                        : '兑换',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  Widget _movieRequests() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _card([
        Text(
          '每次求片 ${(_wallet['rules'] as Map?)?['request_cost']} 积分，未采纳全额退款。最多同时提交5个未完成求片。',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          maxLength: 200,
          decoration: const InputDecoration(labelText: '片名'),
        ),
        TextField(
          controller: _details,
          maxLength: 2000,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '年份、主演、语言等线索（选填）'),
        ),
        FilledButton(
          onPressed: () => _action(() async {
            if (_title.text.trim().isEmpty) throw const ApiException('请输入片名');
            if (!await _confirm(
              '提交将扣除 ${(_wallet['rules'] as Map?)?['request_cost']} 积分，继续？',
            )) {
              return '已取消提交';
            }
            await ApiService().userRequest(
              '/api/user/movie-requests',
              method: 'POST',
              body: {
                'title': _title.text.trim(),
                'details': _details.text.trim(),
              },
            );
            _title.clear();
            _details.clear();
            _requestPage = 1;
            return '求片已提交，请留意站内消息';
          }),
          child: const Text('提交求片'),
        ),
      ]),
      for (final r in _requests)
        _card([
          Text(
            r['title'],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(_states[r['status']] ?? r['status']),
          Text(r['details']),
          const SizedBox(height: 8),
          Text(r['reply'].toString().isEmpty ? '等待管理员处理' : r['reply']),
          Text('${r['cost']} 积分 · ${r['created_at']}'),
          Text(
            r['shared'] == true ? '${r['support_count']} 位同好助力' : '仅自己与管理员可见',
          ),
          if (r['shared'] == true ||
              ['pending', 'processing'].contains(r['status']))
            TextButton(
              onPressed: () => _action(() async {
                final shared = r['shared'] == true;
                if (!shared &&
                    !await _confirm('公开后昵称、作品名与线索会展示给所有访客，可随时收回。邀请同好一起期待？')) {
                  return '保持私密';
                }
                await ApiService().userRequest(
                  '/api/user/movie-requests/share',
                  method: 'POST',
                  body: {'id': r['id'], 'shared': !shared},
                );
                return shared ? '心愿已恢复私密' : '心愿已公开，等待同好亮灯';
              }),
              child: Text(r['shared'] == true ? '收回公开' : '邀请同好助力'),
            ),
        ]),
      _pager(_requestPage, _requestTotal, (p) {
        setState(() => _requestPage = p);
        _load();
      }),
    ],
  );
  Widget _wishWall() {
    final user = context.watch<AppStateProvider>().user ?? {};
    final canSupport = !['observer', 'operator'].contains(user['role']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card([
          const Text(
            '一起期待的故事',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text('给同好亮一盏灯，不消耗积分。助力数为管理员找片优先级提供参考。'),
        ]),
        if (_wall.isEmpty)
          _card([const Text('还没有公开的心愿。求片默认私密，在自己的记录中可主动邀请同好。')]),
        for (final wish in _wall)
          _card([
            Text(
              wish['title'],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text('${wish['username']} · ${_states[wish['status']]}'),
            const SizedBox(height: 10),
            Text(wish['details']),
            Text('${wish['support_count']} 位同好也在期待'),
            TextButton.icon(
              onPressed:
                  !canSupport ||
                      wish['supported'] == true ||
                      wish['user_id'] == user['id']
                  ? null
                  : () => _action(() async {
                      await ApiService().userRequest(
                        '/api/user/movie-requests/support',
                        method: 'POST',
                        body: {'id': wish['id']},
                      );
                      return '为这份期待亮了一盏灯';
                    }),
              icon: const Icon(Icons.favorite_outline),
              label: Text(
                wish['supported'] == true
                    ? '已亮灯'
                    : wish['user_id'] == user['id']
                    ? '我的心愿'
                    : '我也想看',
              ),
            ),
          ]),
        _pager(_wallPage, _wallTotal, (p) {
          setState(() => _wallPage = p);
          _load();
        }),
      ],
    );
  }

  Widget _inbox() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => _action(() async {
            await ApiService().userRequest(
              '/api/user/notifications/read',
              method: 'POST',
              body: {'all': true},
            );
            return '全部消息已读';
          }),
          child: const Text('全部已读'),
        ),
      ),
      if (_notifications.isEmpty) const Center(child: Text('暂时没有通知')),
      for (final n in _notifications)
        _card([
          Row(
            children: [
              if (n['is_read'] != true)
                const Icon(Icons.circle, size: 10, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n['title'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(n['content']),
          Text(n['created_at'], style: const TextStyle(fontSize: 11)),
          if (n['is_read'] != true)
            TextButton(
              onPressed: () => _action(() async {
                await ApiService().userRequest(
                  '/api/user/notifications/read',
                  method: 'POST',
                  body: {
                    'ids': [n['id']],
                  },
                );
                return '消息已读';
              }),
              child: const Text('标为已读'),
            ),
        ]),
      _pager(_inboxPage, _inboxTotal, (p) {
        setState(() => _inboxPage = p);
        _load();
      }),
    ],
  );
}
