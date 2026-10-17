import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// 轻量埋点上报（与网站 tracker.js 对齐）：
/// - 匿名访客 ID 持久化于 SharedPreferences（bllii_vid）
/// - 每次进入主要页面发送一条 page_view（platform=app）
/// - 登录后自动携带 Authorization 关联用户
/// - 全部静默降级，失败不影响任何界面流程
class AnalyticsTracker {
  AnalyticsTracker._internal();
  static final AnalyticsTracker instance = AnalyticsTracker._internal();
  factory AnalyticsTracker() => instance;

  static const String _vidKey = 'bllii_vid';
  static const String _vidPrefix = 'a';

  String? _vid;
  http.Client? _client;

  String get _baseUrl => ApiService().baseUrl;

  http.Client get _httpClient => _client ??= http.Client();

  /// 惰性获取（或生成）匿名访客 ID，与后端 visitor_days 联动构成 App UV。
  Future<String> _visitorId() async {
    final cached = _vid;
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      var vid = prefs.getString(_vidKey) ?? '';
      if (vid.isEmpty) {
        final rand = Random();
        vid = '$_vidPrefix${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
            '${List.generate(8, (_) => rand.nextInt(36).toRadixString(36)).join()}';
        await prefs.setString(_vidKey, vid);
      }
      _vid = vid;
      return vid;
    } catch (_) {
      // 隐私模式等异常：退化为内存 ID，仅本次会话有效
      _vid ??= '$_vidPrefix${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      return _vid!;
    }
  }

  /// 上报一次页面浏览（PV）。[name] 形如 home / anime / play；
  /// [targetId] 为作品 ID（可选）。
  void screen(String name, {int targetId = 0}) {
    _send('page_view', page: 'app://$name', targetId: targetId);
  }

  /// 上报自定义事件（play / search / favorite 等，需在后端事件白名单内）。
  /// [keyword] 仅 search 事件使用，计入后端搜索热词。
  void event(
    String type, {
    String page = 'app://app',
    int targetId = 0,
    int value = 0,
    String keyword = '',
  }) {
    _send(type, page: page, targetId: targetId, value: value, keyword: keyword);
  }

  Future<void> _send(
    String type, {
    required String page,
    int targetId = 0,
    int value = 0,
    String keyword = '',
  }) async {
    try {
      final vid = await _visitorId();
      final token = ApiService().token;
      final body = json.encode({
        'event': type,
        'vid': vid,
        'platform': 'app',
        'page': page,
        'target_id': targetId,
        'dwell_ms': value,
        'keyword': keyword,
      });
      final request = http.Request('POST', Uri.parse('$_baseUrl/api/track'))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'application/json'
        ..body = body;
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      // fire-and-forget：5 秒超时，失败静默
      await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 5))
          .then(http.Response.fromStream);
    } catch (_) {
      // 静默降级：埋点失败不影响业务
    }
  }
}
