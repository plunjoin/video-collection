/* ============================================================
 * bllii PWA Service Worker
 * - 预缓存应用外壳与品牌资源
 * - 页面导航：网络优先，离线时回退到上次访问缓存 / 离线页
 * - 静态资源：stale-while-revalidate
 * - /api/ 请求一律走网络，不缓存
 * 升级时修改 CACHE 版本号即可自动清理旧缓存。
 * ============================================================ */
(function () {
  'use strict';

  var CACHE = 'bllii-shell-v1';
  var PRECACHE = [
    '/',
    '/offline.html',
    '/manifest.webmanifest',
    '/brand/bllii-symbol.svg',
    '/brand/bllii-app-blue.svg',
    '/brand/bllii-app-light.svg',
    '/brand/bllii-horizontal.svg',
    '/icons/icon-192.png',
    '/icons/icon-512.png',
    '/icons/apple-touch-icon.png',
    '/js/tracker.js'
  ];

  self.addEventListener('install', function (event) {
    event.waitUntil(
      caches.open(CACHE).then(function (cache) {
        return cache.addAll(PRECACHE.map(function (url) {
          return new Request(url, { cache: 'reload' });
        }));
      }).then(function () {
        return self.skipWaiting();
      }).catch(function () { /* 预缓存失败不阻塞安装 */ })
    );
  });

  self.addEventListener('activate', function (event) {
    event.waitUntil(
      caches.keys().then(function (keys) {
        return Promise.all(keys.map(function (key) {
          if (key !== CACHE) return caches.delete(key);
        }));
      }).then(function () {
        return self.clients.claim();
      })
    );
  });

  function cacheable(response) {
    return response && response.status === 200 && (response.type === 'basic' || response.type === 'default');
  }

  self.addEventListener('fetch', function (event) {
    var request = event.request;
    if (request.method !== 'GET') return;

    var url = new URL(request.url);
    if (url.origin !== self.location.origin) return;
    if (url.pathname.indexOf('/api/') === 0) return; // API 数据不缓存

    // 页面导航：网络优先，失败回退缓存（实现离线浏览收藏等已访问页面）
    if (request.mode === 'navigate') {
      event.respondWith(
        fetch(request).then(function (response) {
          if (cacheable(response)) {
            var copy = response.clone();
            caches.open(CACHE).then(function (cache) { cache.put(request, copy); });
          }
          return response;
        }).catch(function () {
          return caches.match(request).then(function (hit) {
            if (hit) return hit;
            if (request.url.indexOf('/follow') !== -1) {
              return caches.match('/follow').then(function (follow) { return follow || caches.match('/offline.html'); });
            }
            return caches.match('/offline.html');
          });
        })
      );
      return;
    }

    // 静态资源：stale-while-revalidate
    event.respondWith(
      caches.match(request).then(function (hit) {
        var network = fetch(request).then(function (response) {
          if (cacheable(response)) {
            var copy = response.clone();
            caches.open(CACHE).then(function (cache) { cache.put(request, copy); });
          }
          return response;
        }).catch(function () {
          return hit || Response.error();
        });
        return hit || network;
      })
    );
  });
})();
