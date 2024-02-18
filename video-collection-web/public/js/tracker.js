/* ============================================================
 * bllii 轻量埋点（页面停留 / 推荐点击 / 广告点击 / 搜索）
 * - 匿名访客 ID 存于 localStorage（bllii_vid）
 * - 登录后自动携带 Authorization 关联用户
 * - 离开页面通过 keepalive fetch 上报停留时长
 * - 任意带 data-track / data-track-id / data-track-keyword 的元素点击自动上报
 * 用法：window.blliiTrack.event('search', { keyword: '海贼王' })
 * ============================================================ */
(function () {
  'use strict';

  var VID_KEY = 'bllii_vid';
  var TOKEN_KEY = 'Bllii_token';
  var MIN_DWELL = 800; // 停留不足该值不打扰统计
  var START = Date.now();
  var LEAVE_SENT = false;

  function read(key) {
    try { return localStorage.getItem(key) || ''; } catch (e) { return ''; }
  }

  function visitorId() {
    var v = read(VID_KEY);
    if (!v) {
      v = 'v' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
      try { localStorage.setItem(VID_KEY, v); } catch (e) { /* 隐私模式静默降级 */ }
    }
    return v;
  }

  function payload(type, extra) {
    var data = {
      event: type,
      vid: visitorId(),
      page: location.pathname + location.search,
      target_id: 0,
      dwell_ms: 0,
      keyword: ''
    };
    if (extra) {
      for (var k in extra) {
        if (Object.prototype.hasOwnProperty.call(extra, k)) data[k] = extra[k];
      }
    }
    return data;
  }

  function send(data) {
    try {
      var body = JSON.stringify(data);
      var token = read(TOKEN_KEY);
      var headers = { 'Content-Type': 'application/json' };
      if (token) headers['Authorization'] = 'Bearer ' + token;
      if (navigator.sendBeacon && !token) {
        navigator.sendBeacon('/api/track', new Blob([body], { type: 'application/json' }));
      } else {
        fetch('/api/track', {
          method: 'POST',
          keepalive: true,
          headers: headers,
          body: body
        }).catch(function () { /* 埋点失败静默 */ });
      }
    } catch (e) { /* 埋点失败静默 */ }
  }

  window.blliiTrack = {
    event: function (type, extra) { send(payload(type, extra)); },
    visitorId: visitorId
  };

  send(payload('page_view'));

  function leave() {
    if (LEAVE_SENT) return;
    LEAVE_SENT = true;
    var dwell = Date.now() - START;
    if (dwell >= MIN_DWELL) {
      send(payload('page_leave', { dwell_ms: dwell }));
    }
  }
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') leave();
  });
  window.addEventListener('pagehide', leave);

  // 全局委托：带 data-track 属性的元素点击自动上报
  document.addEventListener('click', function (event) {
    var el = event.target && event.target.closest ? event.target.closest('[data-track]') : null;
    if (!el) return;
    var extra = {
      target_id: parseInt(el.getAttribute('data-track-id') || '0', 10) || 0
    };
    var keyword = el.getAttribute('data-track-keyword');
    if (keyword) extra.keyword = keyword;
    send(payload(el.getAttribute('data-track'), extra));
  }, true);
})();
