/* ============================================================
 * bllii 轻量埋点（页面停留 / 视频卡片曝光 / 点击 / 搜索 / 播放进度）
 * - 匿名访客 ID 存于 localStorage（bllii_vid）
 * - 登录后自动携带 Authorization 关联用户
 * - 离开页面通过 keepalive fetch 上报停留时长
 * - 支持 IntersectionObserver 自动监听列表卡片有效曝光（≥50% 且停留≥1s）
 * - 任意带 data-track 的元素点击自动上报
 * ============================================================ */
(function () {
  'use strict';

  var VID_KEY = 'bllii_vid';
  var TOKEN_KEY = 'Bllii_token';
  var MIN_DWELL = 800; // 停留不足该值不计入离开时长
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
        }).catch(function () { /* 静默降级 */ });
      }
    } catch (e) { /* 静默降级 */ }
  }

  // 全局 API
  window.blliiTrack = {
    event: function (type, extra) { send(payload(type, extra)); },
    progress: function (targetId, percent) {
      send(payload('play_progress', { target_id: targetId, dwell_ms: percent }));
    },
    visitorId: visitorId
  };

  // 1. 初次进入页面 PV
  send(payload('page_view'));

  // 2. 页面离开与停留时长上报
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

  // 3. 全局点击委托：带 data-track 的元素点击自动上报
  document.addEventListener('click', function (event) {
    var el = event.target && event.target.closest ? event.target.closest('[data-track]') : null;
    if (!el) return;
    var targetId = parseInt(el.getAttribute('data-track-id') || '0', 10) || 0;
    var rank = parseInt(el.getAttribute('data-track-rank') || '0', 10) || 0;
    var keyword = el.getAttribute('data-track-keyword') || '';

    var extra = {
      target_id: targetId,
      dwell_ms: rank, // 当为视频点击时，用 dwell_ms 记录其在列表中的展示排名位次
      keyword: keyword
    };
    send(payload(el.getAttribute('data-track'), extra));
  }, true);

  // 4. 卡片曝光监听：IntersectionObserver (≥50% 且停留≥1s 记为 1 次有效曝光)
  function initExposeObserver() {
    if (!('IntersectionObserver' in window)) return;

    var exposeObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        var el = entry.target;
        if (entry.isIntersecting && entry.intersectionRatio >= 0.5) {
          if (!el._exposeTimer && !el._hasExposed) {
            el._exposeTimer = setTimeout(function () {
              el._hasExposed = true;
              var targetId = parseInt(el.getAttribute('data-track-id') || '0', 10) || 0;
              var rank = parseInt(el.getAttribute('data-track-rank') || '0', 10) || 0;
              if (targetId > 0) {
                send(payload('impression', {
                  target_id: targetId,
                  dwell_ms: rank // 曝光时同时带上排名位次
                }));
              }
              exposeObserver.unobserve(el);
            }, 1000); // 视口内停留满 1 秒
          }
        } else {
          if (el._exposeTimer) {
            clearTimeout(el._exposeTimer);
            el._exposeTimer = null;
          }
        }
      });
    }, { threshold: [0.5] });

    // 扫描现有与动态加载的卡片
    function observeCards() {
      var elements = document.querySelectorAll('[data-track-expose]:not([data-observed])');
      elements.forEach(function (el) {
        el.setAttribute('data-observed', 'true');
        exposeObserver.observe(el);
      });
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', observeCards);
    } else {
      observeCards();
    }

    // 监听 DOM 动态追加的卡片（如滚动加载更多）
    if ('MutationObserver' in window) {
      var mutObserver = new MutationObserver(function () {
        observeCards();
      });
      mutObserver.observe(document.body, { childList: true, subtree: true });
    }
  }

  initExposeObserver();
})();
