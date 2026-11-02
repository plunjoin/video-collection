/**
 * 极光现代化 Video.js 流媒体播放器内核 (Aurora Modern Video.js Player Engine)
 * 特性：
 * 1. 深度适配 m3u8 (HLS) / mp4 多流媒体切片
 * 2. 浏览器端滤镜、音效设置与悬停画面预览
 * 3. 画面尺寸与比例完美适配引擎：
 *    - 彻底修复 16:9 / 4:3 / 21:9 比例引起的高度不一致与 ControlBar 悬空/下沉问题
 *    - 强制锁定播放器外壳尺寸，采用容器 100% 填充 + 画面正中央绝对居中渲染 (Contain/Center)
 *    - 内置【📐 比例切换】按键 (默认居中自适应 / 16:9 / 4:3 / 铺满全屏)
 * 4. 控制栏所有按钮与控件高度完全统一 (28px 规范化)，全行垂直绝对居中，杜绝高低参差
 * 5. 顶部全宽精准悬浮进度条 + 左右功能区分离解耦
 * 6. 移动端全手势体系：
 *    - 双击左半屏回退 5 秒 (-5s) + 双击右半屏快速前进 5 秒 (+5s)，带扇形涟漪动效
 *    - 左右滑动屏幕实时快进/后退，带科技感毛玻璃 HUD 浮层精准指示
 *    - 单击切换控制条显隐与防误触
 * 7. 线路秒切菜单、全屏内嵌选集抽屉、自动连播下一集 (带倒计时)、全分辨率响应式自适应
 */

(function (window) {
  'use strict';

  const BRAND_ICON_SPRITE = "<svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n  <symbol id=\"bllii-home\" viewBox=\"0 0 24 24\"><path d=\"m3 11 7-7q2-2 4 0l7 7M5 10v9q0 2 2 2h10q2 0 2-2v-9M10 21v-7h4v7\"/><path d=\"M17 4h3v3\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-search\" viewBox=\"0 0 24 24\"><circle cx=\"10.5\" cy=\"10.5\" r=\"6.5\"/><path d=\"m15.5 15.5 5 5M7.5 9q1-2 3-2\"/><path d=\"M19 4h2M20 3v2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-calendar\" viewBox=\"0 0 24 24\"><rect x=\"4\" y=\"5\" width=\"16\" height=\"16\" rx=\"4\"/><path d=\"M8 3v4m8-4v4M4 10h16M8 14h2m-2 3h2m4-3h2\"/><path d=\"m14 17 1 1 3-3\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-rank\" viewBox=\"0 0 24 24\"><path d=\"M4 20h16M5 17v-5h4v5m1 0V8h4v9m1 0v-6h4v6\"/><path d=\"m10 4 2-2 2 2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-library\" viewBox=\"0 0 24 24\"><path d=\"M7 3h10M5 6h14\"/><rect x=\"3\" y=\"9\" width=\"18\" height=\"12\" rx=\"4\"/><path d=\"m10 12 5 3-5 3z\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-bookmark\" viewBox=\"0 0 24 24\"><path d=\"M6 5q0-2 2-2h8q2 0 2 2v16l-6-4-6 4z\"/><path d=\"M10 7h4m-4 3h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-heart\" viewBox=\"0 0 24 24\"><path d=\"M12 20S3 15 3 8a5 5 0 0 1 9-3 5 5 0 0 1 9 3c0 7-9 12-9 12Z\"/><path d=\"M16 6q2 0 2 2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-star\" viewBox=\"0 0 24 24\"><path d=\"m12 3 3 6 6 1-4.5 4.5 1 6.5-5.5-3-5.5 3 1-6.5L3 10l6-1Z\"/><path d=\"m19 3 1-1m1 4h1\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-bell\" viewBox=\"0 0 24 24\"><path d=\"M8 18h8M9 21h6M5 17c2-2 1-4 1-7a6 6 0 0 1 12 0c0 3-1 5 1 7Z\"/><path d=\"m19 3 2 2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-user\" viewBox=\"0 0 24 24\"><circle cx=\"12\" cy=\"8\" r=\"4\"/><path d=\"M4 21v-2c0-7 16-7 16 0v2M10 8h.1m3.9 0h.1\"/><path d=\"M19 6h2m-1-1v2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-history\" viewBox=\"0 0 24 24\"><path d=\"M4 8a9 9 0 1 1-1 7M3 3v5h5M12 7v5l3 2\"/><path d=\"M4 18h3\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-logout\" viewBox=\"0 0 24 24\"><path d=\"M10 3H6q-2 0-2 2v14q0 2 2 2h4M10 12h11m-4-4 4 4-4 4\"/><path d=\"M8 7h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-play\" viewBox=\"0 0 24 24\"><path d=\"M8 4q-2-1-2 2v12q0 3 2 2l12-7q2-1 0-2Z\"/><path d=\"M2 8h1m-2 4h2m-1 4h1\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-pause\" viewBox=\"0 0 24 24\"><rect x=\"5\" y=\"4\" width=\"4\" height=\"16\" rx=\"2\"/><rect x=\"15\" y=\"4\" width=\"4\" height=\"16\" rx=\"2\"/><path d=\"M11 12h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-prev\" viewBox=\"0 0 24 24\"><path d=\"m18 5-9 7 9 7ZM5 5v14\"/><path d=\"M3 9v6\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-next\" viewBox=\"0 0 24 24\"><path d=\"m6 5 9 7-9 7ZM19 5v14\"/><path d=\"M21 9v6\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-arrow-left\" viewBox=\"0 0 24 24\"><path d=\"M20 12H4m6-6-6 6 6 6\"/><path d=\"M17 8h3\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-arrow-right\" viewBox=\"0 0 24 24\"><path d=\"M4 12h16m-6-6 6 6-6 6\"/><path d=\"M4 16h3\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-chevron-down\" viewBox=\"0 0 24 24\"><path d=\"m5 9 7 7 7-7\"/><path d=\"M11 5h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-check\" viewBox=\"0 0 24 24\"><path d=\"m5 12 5 5L20 6\"/><path d=\"M3 17h3\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-plus\" viewBox=\"0 0 24 24\"><path d=\"M12 5v14M5 12h14\"/><path d=\"M18 4h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-close\" viewBox=\"0 0 24 24\"><path d=\"m6 6 12 12M6 18 18 6\"/><path d=\"M20 3h1\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-shuffle\" viewBox=\"0 0 24 24\"><path d=\"M3 6h3c4 0 8 12 12 12h3m-4-4 4 4-4 3M3 18h3c1 0 3-2 4-4m4-4c1-2 3-4 4-4h3m-4-3 4 3-4 4\"/><path d=\"M3 11h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-sparkles\" viewBox=\"0 0 24 24\"><path d=\"m10 4 2 6 6 2-6 2-2 6-2-6-6-2 6-2Z\"/><path d=\"m19 2 1 3 3 1-3 1-1 3-1-3-3-1 3-1Z\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-smile\" viewBox=\"0 0 24 24\"><rect x=\"3\" y=\"4\" width=\"18\" height=\"16\" rx=\"7\"/><path d=\"M8 10v1m8-1v1m-8 4q4 4 8 0\"/><path d=\"M18 3h3\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-compass\" viewBox=\"0 0 24 24\"><circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"m16 8-2 6-6 2 2-6Z\"/><path d=\"M12 2v2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-moon\" viewBox=\"0 0 24 24\"><path d=\"M20 14A9 9 0 0 1 10 3a9 9 0 1 0 10 11Z\"/><path d=\"m18 3 1 2 2 1-2 1-1 2-1-2-2-1 2-1Z\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-ratio\" viewBox=\"0 0 24 24\"><rect x=\"3\" y=\"5\" width=\"18\" height=\"14\" rx=\"3\"/><path d=\"M7 9h4m-4 0v4m10 2h-4m4 0v-4\"/><path d=\"M11 2h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-routes\" viewBox=\"0 0 24 24\"><path d=\"M3 7h17m-4-4 4 4-4 4M21 17H4m4-4-4 4 4 4\"/><path d=\"M3 3h2m14 18h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-episodes\" viewBox=\"0 0 24 24\"><rect x=\"3\" y=\"4\" width=\"7\" height=\"7\" rx=\"2\"/><rect x=\"14\" y=\"4\" width=\"7\" height=\"7\" rx=\"2\"/><rect x=\"3\" y=\"15\" width=\"7\" height=\"6\" rx=\"2\"/><path d=\"M14 16h7m-7 4h4\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-repeat\" viewBox=\"0 0 24 24\"><path d=\"M4 10V8q0-3 3-3h13m-3-3 3 3-3 3M20 14v2q0 3-3 3H4m3-3-3 3 3 3\"/><path d=\"m10 10 5 2-5 2Z\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-volume\" viewBox=\"0 0 24 24\"><path d=\"M3 9h4l5-5v16l-5-5H3ZM16 8q4 4 0 8\"/><path d=\"M19 5q7 7 0 14\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-muted\" viewBox=\"0 0 24 24\"><path d=\"M3 9h4l5-5v16l-5-5H3ZM16 9l6 6m-6 0 6-6\"/><path d=\"M18 4h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-fullscreen\" viewBox=\"0 0 24 24\"><path d=\"M8 3H5q-2 0-2 2v3m13-5h3q2 0 2 2v3M3 16v3q0 2 2 2h3m8 0h3q2 0 2-2v-3\"/><path d=\"M10 12h4\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-message\" viewBox=\"0 0 24 24\"><path d=\"M7 4h10q4 0 4 4v6q0 4-4 4h-6l-6 3v-4q-2-1-2-3V8q0-4 4-4Z\"/><path d=\"M7 9h10M7 13h5\"/><path d=\"M15 13h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-mail\" viewBox=\"0 0 24 24\"><rect x=\"3\" y=\"5\" width=\"18\" height=\"14\" rx=\"4\"/><path d=\"m4 7 8 6 8-6\"/><path d=\"M17 21h3\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-link\" viewBox=\"0 0 24 24\"><path d=\"m10 8 3-3a4 4 0 0 1 6 6l-3 3m-2 2-3 3a4 4 0 0 1-6-6l3-3m1 5 6-6\"/><path d=\"M3 4h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-lock\" viewBox=\"0 0 24 24\"><rect x=\"4\" y=\"10\" width=\"16\" height=\"11\" rx=\"4\"/><path d=\"M8 10V7a4 4 0 0 1 8 0v3M12 14v3\"/><path d=\"M18 3h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-settings\" viewBox=\"0 0 24 24\"><path d=\"M4 7h16M4 17h16\"/><rect x=\"7\" y=\"4\" width=\"4\" height=\"6\" rx=\"2\"/><rect x=\"14\" y=\"14\" width=\"4\" height=\"6\" rx=\"2\"/><path d=\"M19 3h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-speed\" viewBox=\"0 0 24 24\"><path d=\"M4 18a9 9 0 1 1 16 0M7 9l1 1m4-5v2m5 2-1 1M6 17h12m-6-3 4-3\"/><path d=\"M2 12h2\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-scrubber\" viewBox=\"0 0 24 24\"><path d=\"M7 4q-3-1-3 2v12q0 3 3 2l13-7q2-1 0-2Z\" fill=\"#f6faff\" stroke=\"#4b9fff\"/><path d=\"M8 10v2m5-1v2m-5 3q2 2 4 0\" stroke=\"#9a83ff\"/><path d=\"M1 8h1m-1 4h1m-1 4h1\" stroke=\"#ff89c7\"/></symbol>\n  <symbol id=\"bllii-arrow-up\" viewBox=\"0 0 24 24\"><path d=\"M12 20V4m-6 6 6-6 6 6\"/><path d=\"M4 18v2\" stroke=\"#ff89c7\"/></symbol>\n</svg>\n"; // brand-sprite
  function brandIcon(name, className = '') {
    return `<svg class="bllii-player-icon ${className}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><use href="#bllii-${name}" /></svg>`;
  }

  // 画面比例模式配置
  const ASPECT_MODES = [
    { key: 'auto', name: '居中自适应', label: '比例: 居中', short: '居中' },
    { key: '16:9', name: '16:9 宽屏', label: '比例: 16:9', short: '16:9' },
    { key: '4:3', name: '4:3 经典', label: '比例: 4:3', short: '4:3' },
    { key: 'fill', name: '画面铺满', label: '比例: 铺满', short: '铺满' },
  ];

  // 注入播放器控制条高质感现代样式、比例居中与手势样式
  function ensurePlayerStyles() {
    if (!document.getElementById('bllii-player-icons')) {
      const icons = document.createElement('div');
      icons.id = 'bllii-player-icons';
      icons.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden;pointer-events:none';
      icons.innerHTML = BRAND_ICON_SPRITE;
      document.body.appendChild(icons);
    }
    if (document.getElementById('vplayer-modern-styles')) return;
    const style = document.createElement('style');
    style.id = 'vplayer-modern-styles';
    style.innerHTML = `
      /* 播放器容器尺寸绝对固定在父级外框中，强制干掉 Video.js 针对 4:3 / 21:9 注入的动态 padding-top */
      .vjs-modern-skin,
      .vjs-modern-skin.video-js,
      .vjs-modern-skin.vjs-fluid,
      .vjs-modern-skin.video-js.vjs-fluid {
        font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !important;
        background-color: #000000 !important;
        position: absolute !important;
        top: 0 !important;
        left: 0 !important;
        right: 0 !important;
        bottom: 0 !important;
        width: 100% !important;
        height: 100% !important;
        padding-top: 0 !important; /* 关键：彻底杜绝动态 padding-top 导致高度跳变与悬空 */
        overflow: hidden !important;
        user-select: none;
        -webkit-user-select: none;
        display: block !important; /* 关键：使用标准 block 流，严禁使用 flex 导致子控制栏被垂直居中 */
        box-sizing: border-box !important;
      }
      .vjs-modern-skin.vjs-fill {
        width: 100% !important;
        height: 100% !important;
      }

      /* 核心：视频画面在整个播放器正中央【水平+垂直绝对居中】(Contain/Center) */
      .vjs-modern-skin .vjs-tech {
        width: 100% !important;
        height: 100% !important;
        max-width: 100% !important;
        max-height: 100% !important;
        position: absolute !important;
        top: 50% !important;
        left: 50% !important;
        transform: translate(-50%, -50%) !important;
        object-fit: contain !important; /* 核心：21:9 上下留对称黑边居中，4:3 左右留对称黑边居中 */
        object-position: center center !important;
        margin: 0 !important;
        transition: filter 0.35s cubic-bezier(0.4, 0, 0.2, 1), transform 0.25s ease !important;
      }

      /* 原生居中大播放按钮 */
      .vjs-modern-skin .vjs-big-play-button {
        position: absolute !important;
        top: 50% !important;
        left: 50% !important;
        transform: translate(-50%, -50%) !important;
        margin: 0 !important;
      }

      /* 比例模式 1：16:9 宽屏居中 (自适应容纳) */
      .vjs-modern-skin.vjs-aspect-16-9 .vjs-tech {
        width: 100% !important;
        height: 100% !important;
        max-width: 100% !important;
        max-height: 100% !important;
        aspect-ratio: 16 / 9 !important;
        object-fit: contain !important;
      }

      /* 比例模式 2：4:3 经典比例居中 (高度充满，水平绝对居中，两边黑边均匀) */
      .vjs-modern-skin.vjs-aspect-4-3 .vjs-tech {
        height: 100% !important;
        width: auto !important;
        aspect-ratio: 4 / 3 !important;
        max-width: 100% !important;
        object-fit: contain !important;
      }

      /* 比例模式 3：铺满拉伸模式 */
      .vjs-modern-skin.vjs-aspect-fill .vjs-tech {
        width: 100% !important;
        height: 100% !important;
        object-fit: fill !important;
      }

      /* 控制栏现代化毛玻璃悬浮条：永远绝对吸附在整个播放器大黑框的最底部，绝不悬空，绝不随视频居中 */
      .vjs-modern-skin .vjs-control-bar {
        position: absolute !important;
        left: 0 !important;
        right: 0 !important;
        bottom: 0 !important; /* 核心：死死贴住大黑框的最底边 */
        top: auto !important;
        width: 100% !important;
        height: 48px !important;
        padding: 0 10px !important;
        display: flex !important;
        align-items: center !important;
        justify-content: space-between !important;
        background: linear-gradient(180deg, rgba(3, 7, 18, 0) 0%, rgba(3, 7, 18, 0.78) 30%, rgba(3, 7, 18, 0.98) 100%) !important;
        backdrop-filter: blur(12px) !important;
        -webkit-backdrop-filter: blur(12px) !important;
        border-bottom-left-radius: 12px;
        border-bottom-right-radius: 12px;
        z-index: 20 !important;
        box-sizing: border-box !important;
        margin: 0 !important;
        transform: none !important;
      }

      /* 进度条独立置顶悬浮：横贯 100% 宽度，彻底释放下方按钮控制空间 */
      .vjs-modern-skin .vjs-progress-control {
        position: absolute !important;
        left: 0 !important;
        right: 0 !important;
        top: -14px !important;
        width: 100% !important;
        height: 20px !important;
        display: flex !important;
        align-items: center !important;
        z-index: 25 !important;
        cursor: pointer !important;
        padding: 0 4px !important;
        box-sizing: border-box !important;
        flex: none !important;
      }
      .vjs-modern-skin .vjs-progress-holder {
        height: 4px !important;
        margin: 0 !important;
        border-radius: 9999px !important;
        background-color: rgba(255, 255, 255, 0.22) !important;
        transition: height 0.15s ease !important;
      }
      .vjs-modern-skin .vjs-progress-control:hover .vjs-progress-holder,
      .vjs-modern-skin .vjs-progress-control.vjs-sliding .vjs-progress-holder {
        height: 6px !important;
      }
      .vjs-modern-skin .vjs-play-progress {
        background: linear-gradient(90deg, #6366f1 0%, #a855f7 100%) !important;
        border-radius: 9999px !important;
      }
      .vjs-modern-skin .vjs-play-progress:before {
        font-size: 13px !important;
        position: absolute !important;
        top: -4px !important;
        right: -6px !important;
        color: #fff !important;
        text-shadow: 0 0 8px rgba(99, 102, 241, 0.9) !important;
        opacity: 0;
        transition: opacity 0.15s ease;
      }
      .vjs-modern-skin .vjs-progress-control:hover .vjs-play-progress:before,
      .vjs-modern-skin .vjs-progress-control.vjs-sliding .vjs-play-progress:before {
        opacity: 1;
      }
      .vjs-modern-skin .vjs-load-progress {
        background: rgba(255, 255, 255, 0.3) !important;
        border-radius: 9999px !important;
      }

      /* 隐藏冗余且易造成挤压的倒计时剩余时间 */
      .vjs-modern-skin .vjs-remaining-time {
        display: none !important;
      }

      /* ==================== 控件统一规范 (所有控件高度统一为 28px，严格垂直居中) ==================== */

      /* 1. 原生播放/暂停按钮 */
      .vjs-modern-skin .vjs-play-control {
        width: 32px !important;
        height: 28px !important;
        line-height: 28px !important;
        padding: 0 !important;
        margin: 0 3px 0 0 !important;
        border-radius: 8px !important;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        background: rgba(255, 255, 255, 0.08) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        color: #cbd5e1 !important;
        cursor: pointer !important;
        flex: none !important;
        transition: all 0.2s ease !important;
        box-sizing: border-box !important;
      }
      .vjs-modern-skin .vjs-play-control:hover {
        background: rgba(99, 102, 241, 0.3) !important;
        border-color: rgba(99, 102, 241, 0.6) !important;
        color: #ffffff !important;
      }
      .vjs-modern-skin .vjs-play-control .vjs-icon-placeholder:before {
        line-height: 26px !important;
        font-size: 16px !important;
        height: 100% !important;
        width: 100% !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
      }

      /* 2. 时间显示规范化 (当前时间 / 总时长) */
      .vjs-modern-skin .vjs-time-control {
        height: 28px !important;
        line-height: 28px !important;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        padding: 0 4px !important;
        min-width: auto !important;
        font-size: 12px !important;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace !important;
        font-variant-numeric: tabular-nums !important;
        color: #94a3b8 !important;
        flex: none !important;
        box-sizing: border-box !important;
      }
      .vjs-modern-skin .vjs-current-time-display {
        color: #f8fafc !important;
        font-weight: 600;
      }
      .vjs-modern-skin .vjs-time-divider {
        padding: 0 3px !important;
        min-width: auto !important;
        color: #64748b !important;
      }
      .vjs-modern-skin .vjs-duration-display {
        color: #94a3b8 !important;
      }

      /* Spacer 弹性撑开中间区域 */
      .vjs-modern-skin .vjs-custom-control-spacer {
        flex: 1 1 auto !important;
        display: block !important;
      }

      /* 3. 自定义功能按钮 (画质、比例、线路、选集、连播) 高度严格 28px */
      .vjs-custom-btn {
        cursor: pointer;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        font-size: 12px !important;
        font-weight: 600;
        padding: 0 8px !important;
        margin: 0 2.5px !important;
        border-radius: 8px !important;
        height: 28px !important;
        line-height: 26px !important;
        transition: all 0.2s ease;
        color: #cbd5e1;
        background: rgba(255, 255, 255, 0.08);
        border: 1px solid rgba(255, 255, 255, 0.12);
        user-select: none;
        white-space: nowrap !important;
        flex-shrink: 0 !important;
        box-sizing: border-box !important;
      }
      .vjs-custom-btn:hover {
        background: rgba(99, 102, 241, 0.3);
        border-color: rgba(99, 102, 241, 0.6);
        color: #fff;
        transform: translateY(-1px);
      }
      .vjs-custom-btn svg {
        flex-shrink: 0;
      }

      /* 按钮激活状态 */
      .vjs-btn-ratio.active {
        background: rgba(99, 102, 241, 0.25) !important;
        border-color: #818cf8 !important;
        color: #a5b4fc !important;
      }
      .vjs-btn-autoplay.active {
        background: rgba(16, 185, 129, 0.25) !important;
        border-color: rgba(16, 185, 129, 0.6) !important;
        color: #34d399 !important;
      }

      /* 4. 倍速菜单按钮：严格 28px 高度对齐 */
      .vjs-modern-skin .vjs-playback-rate {
        width: auto !important;
        min-width: 36px !important;
        height: 28px !important;
        line-height: 26px !important;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        padding: 0 6px !important;
        margin: 0 2.5px !important;
        background: rgba(255, 255, 255, 0.08) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 8px !important;
        cursor: pointer !important;
        flex: none !important;
        box-sizing: border-box !important;
      }
      .vjs-modern-skin .vjs-playback-rate .vjs-playback-rate-value {
        font-size: 11px !important;
        line-height: 26px !important;
        height: 26px !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        color: #cbd5e1 !important;
        font-weight: 600 !important;
      }
      .vjs-modern-skin .vjs-playback-rate:hover {
        background: rgba(99, 102, 241, 0.3) !important;
        border-color: rgba(99, 102, 241, 0.6) !important;
      }
      .vjs-modern-skin .vjs-playback-rate:hover .vjs-playback-rate-value {
        color: #fff !important;
      }

      /* 5. 音量控制面板：高度严格 28px 居中 */
      .vjs-modern-skin .vjs-volume-panel {
        height: 28px !important;
        display: inline-flex !important;
        align-items: center !important;
        margin: 0 2.5px !important;
        flex: none !important;
      }
      .vjs-modern-skin .vjs-mute-control {
        width: 30px !important;
        height: 28px !important;
        line-height: 28px !important;
        padding: 0 !important;
        border-radius: 8px !important;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        color: #cbd5e1 !important;
        background: rgba(255, 255, 255, 0.08) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        box-sizing: border-box !important;
      }
      .vjs-modern-skin .vjs-mute-control:hover {
        background: rgba(99, 102, 241, 0.3) !important;
        border-color: rgba(99, 102, 241, 0.6) !important;
        color: #fff !important;
      }
      .vjs-modern-skin .vjs-mute-control .vjs-icon-placeholder:before {
        line-height: 26px !important;
        font-size: 15px !important;
        height: 100% !important;
        width: 100% !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
      }
      .vjs-modern-skin .vjs-volume-panel .vjs-volume-control {
        background: transparent !important;
      }
      .vjs-modern-skin .vjs-volume-bar.vjs-slider-horizontal {
        height: 4px !important;
        border-radius: 9999px !important;
        background-color: rgba(255, 255, 255, 0.2) !important;
      }
      .vjs-modern-skin .vjs-volume-level {
        background: #818cf8 !important;
        border-radius: 9999px !important;
      }

      /* 6. 全屏按钮：高度严格 28px */
      .vjs-modern-skin .vjs-fullscreen-control {
        width: 32px !important;
        height: 28px !important;
        line-height: 28px !important;
        padding: 0 !important;
        margin: 0 0 0 2.5px !important;
        border-radius: 8px !important;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        background: rgba(255, 255, 255, 0.08) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        color: #cbd5e1 !important;
        cursor: pointer !important;
        flex: none !important;
        transition: all 0.2s ease !important;
        box-sizing: border-box !important;
      }
      .vjs-modern-skin .vjs-fullscreen-control:hover {
        background: rgba(99, 102, 241, 0.3) !important;
        border-color: rgba(99, 102, 241, 0.6) !important;
        color: #ffffff !important;
      }
      .vjs-modern-skin .vjs-fullscreen-control .vjs-icon-placeholder:before {
        line-height: 26px !important;
        font-size: 15px !important;
        height: 100% !important;
        width: 100% !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
      }

      /* 线路弹出菜单 */
      .vjs-routes-menu-popup {
        position: absolute;
        bottom: 56px;
        right: 40px;
        background: rgba(15, 23, 42, 0.96);
        backdrop-filter: blur(14px);
        -webkit-backdrop-filter: blur(14px);
        border: 1px solid rgba(255, 255, 255, 0.15);
        border-radius: 12px;
        padding: 6px;
        min-width: 140px;
        max-width: 85vw;
        max-height: 220px;
        overflow-y: auto;
        box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.6);
        display: none;
        z-index: 35;
      }
      .vjs-routes-menu-popup.show {
        display: block;
        animation: vjsFadeInUp 0.2s cubic-bezier(0.16, 1, 0.3, 1);
      }
      .vjs-route-item {
        padding: 8px 12px;
        border-radius: 8px;
        font-size: 12px;
        color: #cbd5e1;
        cursor: pointer;
        transition: background 0.15s;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }
      .vjs-route-item:hover {
        background: rgba(99, 102, 241, 0.25);
        color: #fff;
      }
      .vjs-route-item.selected {
        background: #4f46e5;
        color: #fff;
        font-weight: 700;
      }

      /* 内嵌选集抽屉面板 (支持全屏模式) */
      .vjs-episodes-drawer {
        position: absolute;
        top: 0;
        right: 0;
        bottom: 48px;
        width: 320px;
        max-width: 85%;
        background: rgba(11, 15, 25, 0.96);
        backdrop-filter: blur(16px);
        -webkit-backdrop-filter: blur(16px);
        border-left: 1px solid rgba(255, 255, 255, 0.1);
        z-index: 35;
        display: flex;
        flex-direction: column;
        visibility: hidden;
        opacity: 0;
        pointer-events: none;
        clip-path: inset(0 0 0 100%);
        transition: clip-path .25s ease-out, opacity .2s ease-out;
        box-shadow: -10px 0 25px rgba(0,0,0,0.6);
      }
      .vjs-episodes-drawer.open {
        visibility: visible;
        opacity: 1;
        pointer-events: auto;
        clip-path: inset(0);
      }
      .vjs-drawer-header {
        padding: 12px 16px;
        border-bottom: 1px solid rgba(255, 255, 255, 0.08);
        display: flex;
        align-items: center;
        justify-content: space-between;
      }
      .vjs-drawer-title {
        font-size: 13px;
        font-weight: 700;
        color: #fff;
        display: flex;
        align-items: center;
        gap: 6px;
      }
      .vjs-drawer-close {
        cursor: pointer;
        color: #94a3b8;
        font-size: 20px;
        line-height: 1;
        padding: 4px 8px;
        border-radius: 6px;
        background: transparent;
        border: none;
      }
      .vjs-drawer-close:hover {
        color: #fff;
        background: rgba(255, 255, 255, 0.1);
      }
      .vjs-drawer-body {
        flex: 1;
        padding: 12px;
        overflow-y: auto;
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 8px;
        align-content: start;
      }
      .vjs-drawer-ep-btn {
        padding: 8px 4px;
        text-align: center;
        font-size: 11px;
        border-radius: 8px;
        background: rgba(255, 255, 255, 0.05);
        border: 1px solid rgba(255, 255, 255, 0.08);
        color: #cbd5e1;
        cursor: pointer;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        transition: all 0.15s;
      }
      .vjs-drawer-ep-btn:hover {
        background: rgba(99, 102, 241, 0.3);
        border-color: #6366f1;
        color: #fff;
      }
      .vjs-drawer-ep-btn.active {
        background: #4f46e5;
        border-color: #818cf8;
        color: #fff;
        font-weight: 700;
        box-shadow: 0 0 10px rgba(99, 102, 241, 0.5);
      }

      /* 下一集倒计时卡片 */
      .vjs-next-countdown-card {
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        background: rgba(15, 23, 42, 0.95);
        backdrop-filter: blur(16px);
        -webkit-backdrop-filter: blur(16px);
        border: 1px solid rgba(99, 102, 241, 0.4);
        padding: 18px 22px;
        border-radius: 16px;
        z-index: 40;
        text-align: center;
        box-shadow: 0 20px 30px rgba(0,0,0,0.7);
        display: none;
        animation: vjsScaleIn 0.25s ease-out;
      }
      .vjs-next-countdown-card.show {
        display: block;
      }

      /* Toast 消息提示 */
      .vjs-center-toast {
        position: absolute;
        top: 20px;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(15, 23, 42, 0.92);
        backdrop-filter: blur(8px);
        -webkit-backdrop-filter: blur(8px);
        border: 1px solid rgba(99, 102, 241, 0.4);
        color: #fff;
        padding: 8px 18px;
        border-radius: 9999px;
        font-size: 12px;
        font-weight: 600;
        pointer-events: none;
        z-index: 45;
        opacity: 0;
        transition: opacity 0.3s ease, transform 0.3s ease;
        box-shadow: 0 10px 25px rgba(0,0,0,0.5);
        white-space: nowrap;
      }
      .vjs-center-toast.show {
        opacity: 1;
        transform: translateX(-50%) translateY(8px);
      }

      /* ==================== 移动端手势与 HUD 专属交互层 ==================== */
      .vjs-gesture-layer {
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        bottom: 48px;
        z-index: 8;
        user-select: none;
        -webkit-user-select: none;
        touch-action: pan-y;
        cursor: pointer;
      }

      /* 双击快速快退 / 快进视觉涟漪反馈 (-5s / +5s) */
      .vjs-quick-seek-feedback {
        position: absolute;
        top: 0;
        bottom: 48px;
        width: 36%;
        pointer-events: none;
        z-index: 28;
        display: flex;
        align-items: center;
        justify-content: center;
        opacity: 0;
        transition: opacity 0.25s ease;
      }
      .vjs-quick-seek-feedback.vjs-seek-left {
        left: 0;
        border-top-right-radius: 50%;
        border-bottom-right-radius: 50%;
        background: radial-gradient(circle at left center, rgba(99, 102, 241, 0.4) 0%, rgba(99, 102, 241, 0) 75%);
      }
      .vjs-quick-seek-feedback.vjs-seek-right {
        right: 0;
        border-top-left-radius: 50%;
        border-bottom-left-radius: 50%;
        background: radial-gradient(circle at right center, rgba(99, 102, 241, 0.4) 0%, rgba(99, 102, 241, 0) 75%);
      }
      .vjs-quick-seek-feedback .vjs-seek-content {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 4px;
        color: #fff;
        text-shadow: 0 2px 10px rgba(0, 0, 0, 0.8);
        transform: scale(0.8);
        transition: transform 0.25s cubic-bezier(0.175, 0.885, 0.32, 1.275);
      }
      .vjs-quick-seek-feedback .vjs-seek-text {
        font-size: 14px;
        font-weight: 800;
        letter-spacing: 0.5px;
        font-family: ui-monospace, SFMono-Regular, monospace;
      }
      .vjs-quick-seek-feedback.active {
        opacity: 1;
      }
      .vjs-quick-seek-feedback.active .vjs-seek-content {
        transform: scale(1.1);
      }

      /* 左右滑动快进/后退中央 HUD 浮层 */
      .vjs-gesture-hud {
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%) scale(0.9);
        background: rgba(15, 23, 42, 0.94);
        backdrop-filter: blur(16px);
        -webkit-backdrop-filter: blur(16px);
        border: 1px solid rgba(99, 102, 241, 0.45);
        padding: 14px 22px;
        border-radius: 16px;
        z-index: 32;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        min-width: 150px;
        box-shadow: 0 20px 30px rgba(0, 0, 0, 0.7);
        opacity: 0;
        pointer-events: none;
        transition: opacity 0.2s ease, transform 0.2s ease;
      }
      .vjs-gesture-hud.show {
        opacity: 1;
        transform: translate(-50%, -50%) scale(1);
      }
      .vjs-hud-icon-wrap {
        display: flex;
        align-items: center;
        gap: 6px;
        color: #fff;
      }
      .vjs-hud-time {
        font-size: 13px;
        font-weight: 700;
        color: #f8fafc;
        margin-top: 4px;
        font-family: ui-monospace, SFMono-Regular, monospace;
        letter-spacing: 0.5px;
      }
      .vjs-hud-progress-bg {
        width: 100%;
        height: 4px;
        background: rgba(255, 255, 255, 0.2);
        border-radius: 9999px;
        margin-top: 8px;
        overflow: hidden;
      }
      .vjs-hud-progress-bar {
        height: 100%;
        background: linear-gradient(90deg, #6366f1, #a855f7);
        width: 0%;
        border-radius: 9999px;
        transition: width 0.05s linear;
      }

      /* 动画帧 */
      @keyframes vjsFadeInUp {
        from { opacity: 0; transform: translateY(8px); }
        to { opacity: 1; transform: translateY(0); }
      }
      @keyframes vjsScaleIn {
        from { opacity: 0; transform: translate(-50%, -50%) scale(0.9); }
        to { opacity: 1; transform: translate(-50%, -50%) scale(1); }
      }

      /* ==================== 响应式移动端深度适配 (Media Queries) ==================== */
      @media (max-width: 768px) {
        .vjs-modern-skin .vjs-control-bar {
          height: 44px !important;
          padding: 0 6px !important;
        }
        .vjs-modern-skin .vjs-progress-control {
          top: -12px !important;
          height: 16px !important;
        }
        .vjs-custom-btn {
          font-size: 11px !important;
          padding: 0 5px !important;
          margin: 0 1.5px !important;
          height: 26px !important;
          line-height: 24px !important;
        }
        .vjs-custom-btn svg {
          width: 12px !important;
          height: 12px !important;
          margin-right: 2px !important;
        }
        .vjs-modern-skin .vjs-play-control,
        .vjs-modern-skin .vjs-fullscreen-control {
          height: 26px !important;
          line-height: 26px !important;
        }
        .vjs-modern-skin .vjs-volume-panel .vjs-volume-control {
          display: none !important;
        }
        .vjs-modern-skin .vjs-volume-panel {
          height: 26px !important;
          width: 28px !important;
        }
        .vjs-modern-skin .vjs-mute-control {
          height: 26px !important;
          width: 28px !important;
        }
        .vjs-modern-skin .vjs-time-control {
          height: 26px !important;
          line-height: 26px !important;
          font-size: 11px !important;
        }
        .vjs-modern-skin .vjs-playback-rate {
          height: 26px !important;
          line-height: 24px !important;
        }
        .vjs-episodes-drawer {
          bottom: 44px !important;
        }
        .vjs-gesture-layer {
          bottom: 44px !important;
        }
        .vjs-quick-seek-feedback {
          bottom: 44px !important;
        }
      }

      @media (max-width: 520px) {
        .vjs-custom-btn {
          padding: 0 4px !important;
          margin: 0 1px !important;
          font-size: 10px !important;
        }
        .vjs-modern-skin .vjs-play-control,
        .vjs-modern-skin .vjs-fullscreen-control {
          width: 26px !important;
        }
        .vjs-modern-skin .vjs-playback-rate {
          min-width: 30px !important;
          padding: 0 3px !important;
          margin: 0 1px !important;
        }
        /* 手机竖屏超小宽度下隐藏音量按钮，释放空间给核心按钮 */
        .vjs-modern-skin .vjs-volume-panel {
          display: none !important;
        }
        .vjs-modern-skin .vjs-time-control {
          font-size: 10px !important;
          padding: 0 1px !important;
        }
        .vjs-routes-menu-popup {
          right: 10px !important;
          bottom: 50px !important;
        }
      }
    `;
    style.innerHTML += `
      .vjs-modern-skin { --bllii-blue: #4b9fff; --bllii-pink: #ff89c7; --bllii-ink: #353b58; }
      .bllii-player-icon { width: 21px; height: 21px; display: inline-block; vertical-align: middle; flex: none; }
      .vjs-modern-skin .vjs-big-play-button {
        width: 76px; height: 76px; border-radius: 22px; border: 1px solid #ffffffb0;
        background: #ffffffec; color: #438ff0; box-shadow: 0 8px 25px #00000020;
      }
      .vjs-modern-skin .vjs-big-play-button:hover { background: white; }
      .vjs-modern-skin .vjs-big-play-button .bllii-player-icon { width: 40px; height: 40px; }
      .vjs-modern-skin .vjs-icon-placeholder::before { display: none !important; }
      .vjs-modern-skin .vjs-control-bar {
        background: #15191edd !important; backdrop-filter: blur(10px) !important;
        border-radius: 0 !important; padding-inline: 12px !important; gap: 4px;
      }
      .vjs-modern-skin .vjs-play-progress, .vjs-modern-skin .vjs-volume-level {
        background: linear-gradient(90deg, #4b9fff, #9a83ff 65%, #ff89c7) !important;
      }
      .vjs-modern-skin .vjs-play-progress:before { text-shadow: none !important; color: #ff89c7 !important; }
      .vjs-modern-skin .vjs-custom-btn,
      .vjs-modern-skin .vjs-play-control,
      .vjs-modern-skin .vjs-fullscreen-control,
      .vjs-modern-skin .vjs-mute-control {
        width: 32px !important; min-width: 32px !important; height: 32px !important;
        padding: 0 !important; margin: 0 !important; border-radius: 6px !important;
        display: inline-flex !important; align-items: center !important; justify-content: center !important;
        background: transparent !important; border: 1px solid transparent !important; box-shadow: none !important;
        color: #eef5ff !important; position: relative;
      }
      .vjs-modern-skin .vjs-custom-btn > span { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
      .vjs-modern-skin .vjs-custom-btn svg { width: 20px !important; height: 20px !important; margin: 0 !important; }
      .vjs-modern-skin .vjs-custom-btn.active { color: #91c4ff !important; background: #4b9fff18 !important; }
      .vjs-modern-skin button:hover { border-color: #4b9fff65 !important; }
      .vjs-modern-skin button:focus-visible { outline: 2px solid #ff89c7; outline-offset: -2px; }
      .vjs-modern-skin .vjs-custom-btn::after {
        content: attr(aria-label); position: absolute; bottom: 42px; right: 0; padding: 7px 10px;
        background: #ffffff; color: #353b58; font-size: 11px; border-radius: 4px;
        white-space: nowrap; opacity: 0; pointer-events: none; transition: opacity .15s; box-shadow: 0 4px 20px #00000020;
      }
      .vjs-modern-skin .vjs-custom-btn:hover::after, .vjs-modern-skin .vjs-custom-btn:focus-visible::after { opacity: 1; }
      .vjs-modern-skin .vjs-paused-icon, .vjs-modern-skin .vjs-muted-icon { display: none; }
      .vjs-modern-skin.vjs-playing .vjs-playing-icon { display: none; }
      .vjs-modern-skin.vjs-playing .vjs-paused-icon { display: inline-block; }
      .vjs-modern-skin .vjs-vol-0 .vjs-audible-icon { display: none; }
      .vjs-modern-skin .vjs-vol-0 .vjs-muted-icon { display: inline-block; }
      .vjs-modern-skin .vjs-loading-spinner { border: 0; width: 56px; height: 56px; margin: -28px 0 0 -28px; }
      .vjs-modern-skin .vjs-loading-spinner::before, .vjs-modern-skin .vjs-loading-spinner::after { display: none; }
      .vjs-modern-skin .vjs-loading-spinner .bllii-player-icon { width: 48px; height: 48px; color: #91c4ff; animation: blliiBuffer 1.2s ease-in-out infinite; }
      @keyframes blliiBuffer { 0%,100% { transform: translateX(-3px); opacity: .65; } 50% { transform: translateX(3px); opacity: 1; } }
      .vjs-modern-skin .vjs-routes-menu-popup, .vjs-modern-skin .vjs-episodes-drawer,
      .vjs-modern-skin .vjs-next-countdown-card, .vjs-modern-skin .vjs-menu-content {
        background: #f7fafff5 !important; color: #353b58 !important;
        border: 1px solid #e3ebf7 !important; border-radius: 6px !important; box-shadow: 0 6px 24px #00000018 !important;
      }
      .vjs-modern-skin .vjs-drawer-header { border-color: #e3ebf7; background: #f0f6ff; }
      .vjs-modern-skin .vjs-drawer-title { color: #353b58; }
      .vjs-modern-skin .vjs-drawer-title svg { color: #4b9fff; }
      .vjs-modern-skin .vjs-drawer-close { width: 32px; height: 32px; display: grid; place-items: center; color: #7185a0; }
      .vjs-modern-skin .vjs-drawer-ep-btn, .vjs-modern-skin .vjs-route-item { color: #596e89; background: #eef4fc; border-radius: 4px; border-color: #dfe8f5; }
      .vjs-modern-skin .vjs-drawer-ep-btn.active, .vjs-modern-skin .vjs-route-item.active,
      .vjs-modern-skin .vjs-menu-item.vjs-selected { background: #4b9fff !important; color: white !important; border-color: #4b9fff !important; }
      .vjs-modern-skin .vjs-next-countdown-card [id="countdown-ep-title"] { color: #353b58; }
      .vjs-modern-skin .vjs-next-countdown-card [id="countdown-num-text"] { color: #438ff0; }
      .vjs-modern-skin #btn-next-now { background: #438ff0; color: white; }
      .vjs-modern-skin #btn-next-cancel { background: #e8eff8; color: #596e89; }
      .vjs-modern-skin .vjs-hud-progress-bar { background: linear-gradient(90deg, #4b9fff, #ff89c7); }
      .vjs-modern-skin .vjs-gesture-hud { background: #15191eeb; border-color: #4b9fff55; border-radius: 8px; box-shadow: 0 6px 24px #00000020; }
      .vjs-modern-skin .vjs-hud-delta { color: #91c4ff; }
      .vjs-modern-skin .vjs-center-toast { display: flex; align-items: center; gap: 8px; }
      @media (max-width: 520px) {
        .vjs-modern-skin .vjs-control-bar { padding-inline: 5px !important; gap: 1px; }
        .vjs-modern-skin .vjs-custom-btn, .vjs-modern-skin .vjs-play-control, .vjs-modern-skin .vjs-fullscreen-control { min-width: 27px !important; width: 27px !important; }
        .vjs-modern-skin .vjs-time-control { font-size: 10px !important; min-width: 0 !important; }
        .vjs-modern-skin .vjs-custom-btn::after { display: none; }
        .vjs-modern-skin .vjs-big-play-button { width: 56px; height: 56px; border-radius: 16px; }
        .vjs-modern-skin .vjs-big-play-button .bllii-player-icon { width: 32px; height: 32px; }
      }
      @media (max-width: 400px) {
        .vjs-modern-skin .vjs-control-bar { gap: 0; }
        .vjs-modern-skin .vjs-time-divider { display: none !important; }
        .vjs-modern-skin .vjs-duration::before { content: '/'; margin-right: 2px; }
        .vjs-modern-skin .vjs-playback-rate { margin: 0 !important; min-width: 28px !important; padding-inline: 2px !important; }
        .vjs-modern-skin .vjs-custom-control-spacer { min-width: 0; }
      }
      @media (prefers-reduced-motion: reduce) { .vjs-modern-skin *, .vjs-modern-skin *::before, .vjs-modern-skin *::after { animation: none !important; transition: none !important; } }
    `;
    document.head.appendChild(style);
  }

  function ensureBrowserFeatureStyles() {
    if (document.getElementById('bllii-browser-feature-styles')) return;
    const style = document.createElement('style');
    style.id = 'bllii-browser-feature-styles';
    style.textContent = `
      .vjs-modern-skin .vjs-control.vjs-button .vjs-icon-placeholder::before,
      .vjs-modern-skin .vjs-control.vjs-button .vjs-icon-placeholder::after,
      .vjs-modern-skin .vjs-big-play-button .vjs-icon-placeholder::before { content: none !important; display: none !important; }
      .vjs-modern-skin .vjs-icon-placeholder { display: inline-flex; align-items: center; justify-content: center; }
      .vjs-modern-skin .vjs-control-bar > .vjs-playback-rate {
        position: relative; width: 34px !important; min-width: 34px !important; height: 32px !important;
        padding: 0 !important; margin: 0 !important; background: transparent !important; border: 0 !important; border-radius: 6px !important;
      }
      .vjs-modern-skin .vjs-playback-rate > button.vjs-playback-rate {
        position: absolute; inset: 0; width: 100% !important; height: 100% !important; min-width: 0 !important;
        padding: 0 !important; margin: 0 !important; background: transparent !important; border: 0 !important; border-radius: 6px !important;
      }
      .vjs-modern-skin .vjs-playback-rate .vjs-playback-rate-value {
        position: absolute; inset: 0; height: 32px !important; line-height: 32px !important; pointer-events: none;
        color: #eef5ff !important; font-size: 11px !important; font-weight: 600;
      }
      .vjs-modern-skin .vjs-playback-rate .vjs-menu { bottom: 42px; margin-bottom: 0; width: 64px; left: 50%; margin-left: -32px; }
      .vjs-modern-skin .vjs-playback-rate .vjs-menu-content { padding: 5px; width: 100% !important; left: 0 !important; max-height: min(220px, 50vh) !important; }
      .vjs-modern-skin .vjs-playback-rate .vjs-menu-item { font: 12px/2.5 system-ui,sans-serif; border-radius: 4px; color: #596e89; }
      .vjs-modern-skin .vjs-custom-btn:hover { transform: none; }
      .vjs-modern-skin .vjs-play-progress::before { content: none !important; display: none !important; }
      .bllii-seek-mascot { position: absolute; right: -10px; top: -9px; width: 23px; height: 23px; pointer-events: none; z-index: 3; }
      .bllii-seek-mascot .bllii-player-icon { width: 23px; height: 23px; }
      .vjs-modern-skin .vjs-tech { filter: var(--bllii-picture-filter, none) !important; }
      .vjs-modern-skin .vjs-progress-control .vjs-mouse-display { display: none !important; }
      .bllii-frame-preview { position: absolute; bottom: 80px; width: 184px; max-width: calc(100% - 16px); border: 2px solid #ffffff; border-radius: 6px; background: #15191e; box-shadow: 0 6px 24px #00000030; z-index: 40; overflow: hidden; pointer-events: none; }
      .bllii-frame-preview[hidden] { display: none !important; }
      .bllii-frame-preview__media { position: relative; aspect-ratio: 16/9; overflow: hidden; }
      .bllii-frame-preview__media > .video-js { position: absolute; inset: 0; width: 100%; height: 100%; }
      .bllii-frame-preview .vjs-control-bar, .bllii-frame-preview .vjs-big-play-button, .bllii-frame-preview .vjs-loading-spinner, .bllii-frame-preview .vjs-error-display { display: none !important; }
      .bllii-frame-preview .video-js { opacity: 0; transition: opacity .15s; }
      .bllii-frame-preview.is-ready .video-js { opacity: 1; }
      .bllii-frame-preview__state { position: absolute; inset: 0; display: grid; align-content: center; justify-items: center; gap: 8px; color: #a7cfff; font: 11px system-ui,sans-serif; }
      .bllii-frame-preview.is-ready .bllii-frame-preview__state { display: none; }
      .bllii-frame-preview__time { display: block; padding: 6px; text-align: center; font: 11px ui-monospace,monospace; color: #eef5ff; background: #252b32; }
      .bllii-settings-panel {
        position: fixed; margin: auto; inset: 0; width: 330px; max-width: calc(100vw - 24px); max-height: calc(100dvh - 32px); overflow: auto;
        padding: 0; background: #f9fbff; color: #353b58; border: 1px solid #dce8f8; border-radius: 8px;
        box-shadow: 0 18px 60px #15191e40; font: 13px/1.5 system-ui,sans-serif; user-select: auto;
      }
      .bllii-settings-panel::backdrop { background: #15191e35; }
      .bllii-settings-panel[open] { animation: blliiIris .2s ease-out; }
      @keyframes blliiIris { from { clip-path: inset(0 0 100% 0); opacity: .5; } to { clip-path: inset(0); opacity: 1; } }
      .bllii-settings-panel header { display: flex; align-items: center; justify-content: space-between; padding: 14px 16px; border-bottom: 1px solid #e4ebf5; }
      .bllii-settings-panel header strong { display: inline-flex; align-items: center; gap: 8px; font-size: 14px; }
      .bllii-settings-panel header .bllii-player-icon { color: #438ff0; }
      .bllii-settings-panel button { cursor: pointer; font: inherit; }
      .bllii-settings-panel .bllii-panel-close { display: grid; place-items: center; width: 30px; height: 30px; border-radius: 4px; color: #7d899b; }
      .bllii-settings-tabs { display: flex; padding: 12px 16px 0; gap: 18px; }
      .bllii-settings-tabs button { padding: 6px 0; border-bottom: 2px solid transparent; color: #7d899b; }
      .bllii-settings-tabs button[aria-selected="true"] { color: #438ff0; border-color: #ff89c7; }
      .bllii-settings-body { padding: 16px; }
      .bllii-settings-panel [hidden] { display: none !important; }
      .bllii-setting-row { display: block; margin-bottom: 16px; }
      .bllii-setting-row > span { display: flex; justify-content: space-between; gap: 12px; margin-bottom: 9px; }
      .bllii-setting-row output { color: #438ff0; font-variant-numeric: tabular-nums; }
      .bllii-setting-row input[type="range"] { display: block; width: 100%; accent-color: #4b9fff; height: 18px; }
      .bllii-setting-row select { width: 100%; padding: 8px 10px; background: white; color: #353b58; border: 1px solid #dce8f8; border-radius: 4px; font: inherit; }
      .bllii-setting-row select:disabled { opacity: .5; }
      .bllii-sound-state { color: #8290a4; margin: 12px 0; font-size: 12px; }
      .bllii-settings-panel footer { display: flex; justify-content: space-between; align-items: center; padding: 12px 16px; border-top: 1px solid #e4ebf5; }
      .bllii-settings-panel footer button { display: inline-flex; align-items: center; gap: 6px; color: #5c7da5; }
      .bllii-settings-panel footer small { color: #99a4b3; font-size: 10px; }
      @media (max-width: 520px) { .vjs-modern-skin .vjs-control-bar > .vjs-playback-rate { width: 30px !important; min-width: 30px !important; } }
      @media (prefers-reduced-motion: reduce) { .bllii-settings-panel[open] { animation: none; } }
    `;
    document.head.appendChild(style);
  }

  // 只在客户端处理 VOD；直播保留原始地址，以便播放器持续刷新列表。
  const AD_KEYWORDS = ['guanggao', 'ad.', '/ad/', '/ads/', 'advert', 'union', 'adwords', 'open.ad', 'tg.mp4', 'tg.ts', 'banner'];

  function isMasterPlaylist(content) {
    return /^#EXT-X-(?:STREAM-INF|I-FRAME-STREAM-INF):/m.test(content);
  }

  function rewritePlaylistLine(line, originURL) {
    if (!line || line.startsWith('#')) {
      return line.replace(/URI="([^"]+)"/g, (_, uri) => `URI="${new URL(uri, originURL).href}"`);
    }
    return new URL(line, originURL).href;
  }

  function segmentSequence(uri) {
    const name = new URL(uri).pathname.split('/').pop();
    const match = name.match(/(?:^|[^0-9])([0-9]+)\.(?:ts|image|jpeg|jpg|png|webp|m4s|mp4)(?:$|[^a-z])/i);
    return match ? BigInt(match[1]) : null;
  }

  function cleanPlaylist(content, originURL, options = {}) {
    const opts = { enableFilter: true, filterHeadAd: true, filterMiddleAd: true, maxHeadAdDuration: 60, maxMiddleAdDuration: 90, blacklistKeywords: AD_KEYWORDS, ...options };
    const lines = content.replace(/^\uFEFF/, '').split(/\r?\n/).map(line => line.trim()).filter(Boolean);
    if (lines[0] !== '#EXTM3U') throw new Error('Invalid M3U8 playlist');
    if (isMasterPlaylist(content) || !lines.includes('#EXT-X-ENDLIST') || lines.some(line => /^#EXT-X-(?:PART|SKIP|PRELOAD-HINT):/.test(line))) {
      return lines.map(line => rewritePlaylistLine(line, originURL)).join('\n');
    }
    const header = [], footer = [], groups = [];
    let group = { items: [], boundary: false, duration: 0 };
    let tags = [], duration = 0, key = '', map = '', sequence = 0n, rangeEnd = 0, rangeURI = '';
    const mediaSequence = lines.find(line => line.startsWith('#EXT-X-MEDIA-SEQUENCE:'));
    if (mediaSequence) sequence = BigInt(mediaSequence.split(':')[1].trim());
    let segmentIndex = 0n;
    for (const rawLine of lines) {
      const line = rewritePlaylistLine(rawLine, originURL);
      if (line === '#EXT-X-DISCONTINUITY') {
        if (group.items.length) groups.push(group);
        group = { items: [], boundary: true, duration: 0 };
      } else if (line === '#EXT-X-ENDLIST') {
        footer.push(line);
      } else if (line.startsWith('#EXT-X-KEY:')) {
        key = line;
      } else if (line.startsWith('#EXT-X-MAP:')) {
        map = line;
      } else if (line.startsWith('#EXTINF:')) {
        duration = Number.parseFloat(line.slice(8));
        if (!Number.isFinite(duration)) throw new Error('Invalid segment duration');
        tags.push(line);
      } else if (line.startsWith('#')) {
        if (!groups.length && !group.items.length && !tags.length && !line.startsWith('#EXT-X-BYTERANGE:')) header.push(line);
        else tags.push(line);
      } else {
        // 显式保存原始加密 IV 和字节偏移，删片后仍能解密和定位后续切片。
        let segmentKey = key;
        if (key.includes('METHOD=AES-128') && !/(?:[:,])IV=/.test(key)) {
          segmentKey += `,IV=0x${(sequence + segmentIndex).toString(16).padStart(32, '0')}`;
        }
        tags = tags.map(tag => {
          if (!tag.startsWith('#EXT-X-BYTERANGE:')) return tag;
          const [length, offset] = tag.slice(17).split('@').map(Number);
          if (!Number.isFinite(length)) throw new Error('Invalid byte range');
          const start = offset ?? (rangeURI === line ? rangeEnd : 0);
          rangeEnd = start + length;
          rangeURI = line;
          return `#EXT-X-BYTERANGE:${length}@${start}`;
        });
        group.items.push({ uri: line, tags, key: segmentKey, map, duration, seq: segmentSequence(line), ad: opts.enableFilter && opts.blacklistKeywords.some(word => word && line.toLowerCase().includes(word.toLowerCase())) });
        group.duration += duration;
        tags = []; duration = 0; segmentIndex++;
      }
    }
    if (group.items.length) groups.push(group);
    for (const item of groups) {
      const seqs = item.items.map(segment => segment.seq).filter(seq => seq !== null);
      item.hasSeq = seqs.length > 0 && seqs.length >= item.items.length / 2;
      if (item.hasSeq) {
        item.min = seqs.reduce((a, b) => a < b ? a : b);
        item.max = seqs.reduce((a, b) => a > b ? a : b);
      }
    }
    const ads = groups.map(() => false);
    if (opts.enableFilter) {
      if (opts.filterMiddleAd) {
        for (let i = 1; i < groups.length - 1; i++) {
          const prev = groups[i - 1], curr = groups[i], next = groups[i + 1];
          if (!curr.boundary || !next.boundary || curr.duration > opts.maxMiddleAdDuration) continue;
          const before = prev.items.at(-1).seq, after = next.items[0].seq;
          const detour = before !== null && after !== null && after - before === 1n &&
            (curr.items.every(item => item.seq !== null && item.seq > after) || curr.items.every(item => item.seq !== null && item.seq < before));
          const outlier = prev.hasSeq && curr.hasSeq && next.hasSeq &&
            ((curr.min - prev.max > 50n && curr.max - next.min > 50n && next.min - prev.max >= 0n && next.min - prev.max <= 15n) || (curr.min >= 10000n && prev.max < 2000n && next.min < 2000n));
          ads[i] = detour || outlier || (curr.duration <= 20 && curr.items.length <= 6 && prev.items.length >= 8 && next.items.length >= 8);
        }
      }
      if (opts.filterHeadAd && groups.length >= 2 && !ads[1]) {
        const head = groups[0], next = groups[1];
        ads[0] = head.duration <= opts.maxHeadAdDuration && head.hasSeq && next.hasSeq &&
          ((head.min > 1000n && next.min <= 5n) || (next.boundary && head.max >= next.min));
      }
      if (opts.filterMiddleAd && groups.length >= 2) {
        const last = groups.at(-1), prev = groups.at(-2);
        ads[groups.length - 1] = !ads[groups.length - 2] && last.boundary && last.duration <= opts.maxMiddleAdDuration && last.hasSeq && prev.hasSeq && last.min - prev.max > 100n;
      }
    }
    const out = [...header];
    let emittedKey = '', emittedMap = '', previous = null, previousIndex = -1, kept = 0;
    for (let i = 0; i < groups.length; i++) {
      const curr = groups[i];
      if (ads[i]) continue;
      const items = curr.items.filter(item => !item.ad);
      if (!items.length) continue;
      const removedBetween = i > previousIndex + 1;
      const difference = previous?.seq !== null && previous?.seq !== undefined && items[0].seq !== null ? items[0].seq - previous.seq : null;
      if (curr.boundary && previous && !(removedBetween && difference !== null && difference >= 0n && difference <= 2n)) out.push('#EXT-X-DISCONTINUITY');
      for (const item of items) {
        if (item.key && item.key !== emittedKey) { out.push(item.key); emittedKey = item.key; }
        if (item.map && item.map !== emittedMap) { out.push(item.map); emittedMap = item.map; }
        out.push(...item.tags, item.uri); kept++;
      }
      previous = items.at(-1); previousIndex = i;
    }
    // 不输出空列表；规则过度命中时继续使用完整正片列表。
    if (!kept && segmentIndex > 0n) return cleanPlaylist(content, originURL, { ...opts, enableFilter: false });
    return [...out, ...footer].join('\n');
  }

  async function prepareClientPlaylist(url, { signal, options = {}, createURL = text => URL.createObjectURL(new Blob([text], { type: 'application/vnd.apple.mpegurl' })), revokeURL = url => URL.revokeObjectURL(url), fetchPlaylist = fetch } = {}) {
    const urls = [], cache = new Map();
    const dispose = () => urls.splice(0).forEach(revokeURL);
    async function visit(target, parents = []) {
      if (parents.includes(target) || parents.length > 8) throw new Error('Playlist nesting limit');
      if (cache.has(target)) return cache.get(target);
      if (cache.size >= 64) throw new Error('Playlist count limit');
      const task = (async () => {
        const requestSignal = AbortSignal.any([...(signal ? [signal] : []), AbortSignal.timeout(10000)]);
        const response = await fetchPlaylist(target, { signal: requestSignal });
        if (!response.ok) throw new Error(`Playlist HTTP ${response.status}`);
        const content = await response.text();
        const origin = response.url || target;
        let cleaned = cleanPlaylist(content, origin, options);
        if (isMasterPlaylist(content)) {
          const result = [];
          for (const line of cleaned.split('\n')) {
            if (!line.startsWith('#')) result.push(await visit(line, [...parents, target]));
            else if (/^#EXT-X-(?:MEDIA|I-FRAME-STREAM-INF):/.test(line) && /URI="/.test(line)) {
              const child = line.match(/URI="([^"]+)"/)[1];
              result.push(line.replace(/URI="[^"]+"/, `URI="${await visit(child, [...parents, target])}"`));
            } else result.push(line);
          }
          cleaned = result.join('\n');
        } else if (!content.includes('#EXT-X-ENDLIST')) {
          // 静态 Blob 无法刷新直播；整个主列表回退到远程地址。
          throw new Error('Live playlist requires remote refresh');
        }
        signal?.throwIfAborted();
        const local = createURL(cleaned);
        urls.push(local);
        return local;
      })();
      cache.set(target, task);
      return task;
    }
    try { return { url: await visit(url), dispose }; }
    catch (error) { dispose(); throw error; }
  }

  // 播放器类
  class ModernVideoPlayer {
    constructor(elementId, options = {}) {
      this.elementId = elementId;
      this.options = Object.assign({
        autoplay: true,
        controls: true,
        preload: 'auto',
        playbackRates: [0.75, 1, 1.25, 1.5, 2],
        autoplayNextDefault: true,
        nextCountdownSec: 3,
        onEpisodeChange: null,
        onRouteChange: null,
        onTimeUpdate: null,
        initialTime: 0,
        cleanM3U8: true, // 默认开启智能切片广告过滤
        cleanOptions: {}, // 客户端切片过滤规则
      }, options);

      this.player = null;
      this.playlistResource = null;
      this.playlistAbort = null;
      this.sourceGeneration = 0;
      this.currentVideo = null;
      this.currentRouteIndex = 0;
      this.currentEpisodeIndex = 0;
      this.routes = [];
      this.episodes = [];
      this.pendingSeekTime = this.options.initialTime || 0;
      this.lastTimeUpdateReport = 0;
      
      // 读取本地持久化设置
      const savedAutoplay = localStorage.getItem('vplayer_autoplay_next');
      this.isAutoplayNext = savedAutoplay !== null ? savedAutoplay === 'true' : this.options.autoplayNextDefault;

      // 画面比例模式 (默认 auto 居中自适应, 支持 16:9, 4:3, fill)
      this.aspectRatio = localStorage.getItem('vplayer_aspect_ratio') || 'auto';

      this.countdownTimer = null;
      this.countdownLeft = 0;

      ensurePlayerStyles();
      this.initPlayer();
    }

    initPlayer() {
      const el = document.getElementById(this.elementId);
      if (!el) {
        console.error('ModernVideoPlayer: 目标 DOM 未找到 #' + this.elementId);
        return;
      }

      // 如果已有实例先释放
      if (videojs.getPlayer(this.elementId)) {
        videojs.getPlayer(this.elementId).dispose();
      }

      // 初始化 Video.js：彻底关闭 fluid，采用 fill 填充容器模式保证尺寸稳定一致
      this.player = videojs(this.elementId, {
        controls: true,
        autoplay: this.options.autoplay,
        preload: this.options.preload,
        playbackRates: this.options.playbackRates,
        fluid: false, // 彻底关闭高度抖动！杜绝根据影片比例篡改高度
        fill: true,   // 恒定填满外层容器
        controlBar: {
          children: [
            'playToggle',
            'currentTimeDisplay',
            'timeDivider',
            'durationDisplay',
            'progressControl',
            'customControlSpacer',
            'playbackRateMenuButton',
            'volumePanel',
            'fullscreenToggle'
          ]
        },
        html5: {
          vhs: {
            overrideNative: true,
            enableLowInitialPlaylist: true,
            smoothQualityChange: true,
          }
        },
        userActions: {
          hotkeys: false
        }
      });

      this.player.ready(() => {
        const playerEl = this.player.el();
        playerEl.classList.add('vjs-modern-skin');

        // 应用比例模式 (16:9, 4:3 或 默认居中)
        this.applyAspectRatio(this.aspectRatio, false);

        this.injectCustomControls();
        const nativeIcon = (selector, markup) => {
          const placeholder = playerEl.querySelector(selector + ' .vjs-icon-placeholder');
          if (placeholder) placeholder.innerHTML = markup;
        };
        nativeIcon('.vjs-play-control', brandIcon('play'));
        nativeIcon('.vjs-mute-control', brandIcon('volume'));
        nativeIcon('.vjs-fullscreen-control', brandIcon('fullscreen'));
        nativeIcon('.vjs-big-play-button', brandIcon('play'));
        const spinner = playerEl.querySelector('.vjs-loading-spinner');
        if (spinner) spinner.insertAdjacentHTML('beforeend', brandIcon('play'));
        this.injectOverlays();
        this.setupGestureSystem();
        this.setupResponsiveObserver();
        this.bindEvents();
        this.setupBrowserFeatures();
      });
    }

    // 在 ControlBar 注入设置、画面比例、线路、选集、自动连播
    injectCustomControls() {
      const controlBar = this.player.getChild('controlBar');
      if (!controlBar) return;
      const cbEl = controlBar.el();

      this.btnSettings = document.createElement('button');
      this.btnSettings.type = 'button';
      this.btnSettings.className = 'vjs-custom-btn vjs-btn-settings';
      this.btnSettings.title = '放映设置';
      this.btnSettings.innerHTML = brandIcon('settings');
      this.btnSettings.onclick = (e) => {
        e.stopPropagation();
        this.openSettings();
      };

      // 2. 画面比例切换按钮 (居中自适应 / 16:9 / 4:3 / 铺满)
      this.btnRatio = document.createElement('button');
      this.btnRatio.type = 'button';
      this.btnRatio.className = `vjs-custom-btn vjs-btn-ratio ${this.aspectRatio !== 'auto' ? 'active' : ''}`;
      this.btnRatio.title = '画面比例与尺寸 (居中自适应 / 16:9 / 4:3 / 铺满)';
      this.btnRatio.innerHTML = `
        ${brandIcon('ratio')}
        <span class="ratio-text">比例: 居中</span>
      `;
      this.btnRatio.onclick = (e) => {
        e.stopPropagation();
        this.toggleAspectRatio();
      };

      // 3. 线路切换按钮
      this.btnRoutes = document.createElement('button');
      this.btnRoutes.type = 'button';
      this.btnRoutes.className = 'vjs-custom-btn vjs-btn-routes';
      this.btnRoutes.title = '切换播放线路';
      this.btnRoutes.innerHTML = `
        ${brandIcon('routes')}
        <span class="route-label">线路 1</span>
      `;
      this.btnRoutes.onclick = (e) => {
        e.stopPropagation();
        this.toggleRoutesMenu();
      };

      // 4. 选集按钮
      this.btnEpisodes = document.createElement('button');
      this.btnEpisodes.type = 'button';
      this.btnEpisodes.className = 'vjs-custom-btn vjs-btn-episodes';
      this.btnEpisodes.title = '选集播放列表 (支持全屏)';
      this.btnEpisodes.innerHTML = `
        ${brandIcon('episodes')}
        <span>选集</span>
      `;
      this.btnEpisodes.onclick = (e) => {
        e.stopPropagation();
        this.toggleEpisodesDrawer();
      };

      // 5. 自动连播开关
      this.btnAutoplay = document.createElement('button');
      this.btnAutoplay.type = 'button';
      this.btnAutoplay.className = `vjs-custom-btn vjs-btn-autoplay ${this.isAutoplayNext ? 'active' : ''}`;
      this.btnAutoplay.title = '自动播放下一集开关 (默认开启)';
      this.btnAutoplay.innerHTML = `
        ${brandIcon('repeat')}
        <span class="autoplay-text">连播: 开</span>
      `;
      this.btnAutoplay.onclick = (e) => {
        e.stopPropagation();
        this.toggleAutoplayNext();
      };

      // 控件顺序编排：放置在倍速/音量/全屏按钮左侧，保持右侧功能集中
      const playbackBtn = controlBar.getChild('playbackRateMenuButton');
      const volumeBtn = controlBar.getChild('volumePanel');
      const fullscreenBtn = controlBar.getChild('fullscreenToggle');

      const targetAnchor = playbackBtn ? playbackBtn.el() : (volumeBtn ? volumeBtn.el() : (fullscreenBtn ? fullscreenBtn.el() : null));

      if (targetAnchor) {
        cbEl.insertBefore(this.btnSettings, targetAnchor);
        cbEl.insertBefore(this.btnRatio, targetAnchor);
        cbEl.insertBefore(this.btnRoutes, targetAnchor);
        cbEl.insertBefore(this.btnEpisodes, targetAnchor);
        cbEl.insertBefore(this.btnAutoplay, targetAnchor);
      } else {
        cbEl.appendChild(this.btnSettings);
        cbEl.appendChild(this.btnRatio);
        cbEl.appendChild(this.btnRoutes);
        cbEl.appendChild(this.btnEpisodes);
        cbEl.appendChild(this.btnAutoplay);
      }

      [this.btnSettings, this.btnRatio, this.btnRoutes, this.btnEpisodes, this.btnAutoplay].forEach(button => {
        button.setAttribute('aria-label', button.title);
      });
      this.updateBtnLabels();
    }

    // 应用画面比例 (支持 auto居中 / 16:9 / 4:3 / fill)
    applyAspectRatio(ratioKey, showToast = true) {
      this.aspectRatio = ratioKey;
      const playerEl = this.player ? this.player.el() : null;
      if (playerEl) {
        playerEl.classList.remove('vjs-aspect-16-9', 'vjs-aspect-4-3', 'vjs-aspect-fill');
        if (ratioKey === '16:9') {
          playerEl.classList.add('vjs-aspect-16-9');
        } else if (ratioKey === '4:3') {
          playerEl.classList.add('vjs-aspect-4-3');
        } else if (ratioKey === 'fill') {
          playerEl.classList.add('vjs-aspect-fill');
        }
      }

      if (this.btnRatio) {
        if (ratioKey !== 'auto') {
          this.btnRatio.classList.add('active');
        } else {
          this.btnRatio.classList.remove('active');
        }
      }

      this.updateBtnLabels();
      localStorage.setItem('vplayer_aspect_ratio', this.aspectRatio);

      if (showToast) {
        const mode = ASPECT_MODES.find(m => m.key === ratioKey) || ASPECT_MODES[0];
        this.showToast(`📐 画面比例: ${mode.name}`);
      }
    }

    // 循环切换画面比例
    toggleAspectRatio() {
      const curIdx = ASPECT_MODES.findIndex(m => m.key === this.aspectRatio);
      const nextIdx = (curIdx + 1) % ASPECT_MODES.length;
      this.applyAspectRatio(ASPECT_MODES[nextIdx].key, true);
    }

    // 注入弹出层、手势图层与反馈浮层
    injectOverlays() {
      const playerEl = this.player.el();

      // 1. Toast
      this.toastEl = document.createElement('div');
      this.toastEl.className = 'vjs-center-toast';
      playerEl.appendChild(this.toastEl);

      // 2. 线路弹窗菜单
      this.routesMenuEl = document.createElement('div');
      this.routesMenuEl.className = 'vjs-routes-menu-popup';
      playerEl.appendChild(this.routesMenuEl);

      // 3. 选集抽屉
      this.drawerEl = document.createElement('div');
      this.drawerEl.className = 'vjs-episodes-drawer';
      this.drawerEl.innerHTML = `
        <div class="vjs-drawer-header">
          <div class="vjs-drawer-title">
            ${brandIcon('episodes')}
            <span id="drawer-video-title">剧集选集</span>
          </div>
          <button class="vjs-drawer-close" title="关闭选集">&times;</button>
        </div>
        <div class="vjs-drawer-body" id="drawer-episodes-list"></div>
      `;
      this.drawerEl.querySelector('.vjs-drawer-close').onclick = () => this.closeEpisodesDrawer();
      this.drawerEl.querySelector('.vjs-drawer-close').innerHTML = brandIcon('close');
      this.drawerEl.querySelector('.vjs-drawer-close').setAttribute('aria-label', '关闭选集');
      playerEl.appendChild(this.drawerEl);

      // 4. 自动连播倒计时卡片
      this.countdownCard = document.createElement('div');
      this.countdownCard.className = 'vjs-next-countdown-card';
      this.countdownCard.innerHTML = `
        <div class="text-xs text-indigo-400 font-bold uppercase tracking-wider mb-1">即将连播下一集</div>
        <div id="countdown-ep-title" class="text-base font-bold text-white mb-2">第02集</div>
        <div id="countdown-num-text" class="text-3xl font-black text-indigo-400 mb-4">3</div>
        <div class="flex items-center justify-center gap-2">
          <button id="btn-next-now" class="px-4 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg text-xs font-bold transition">立即播放</button>
          <button id="btn-next-cancel" class="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded-lg text-xs font-medium transition">取消</button>
        </div>
      `;
      playerEl.appendChild(this.countdownCard);

      this.countdownCard.querySelector('#btn-next-now').onclick = () => {
        this.clearCountdown();
        this.playNextEpisode();
      };
      this.countdownCard.querySelector('#btn-next-cancel').onclick = () => {
        this.clearCountdown();
        this.showToast('已取消自动连播');
      };

      // 5. 移动端触摸手势交互层
      this.gestureLayer = document.createElement('div');
      this.gestureLayer.className = 'vjs-gesture-layer';
      playerEl.appendChild(this.gestureLayer);

      // 6. 双击左/右侧反馈波纹层
      this.quickSeekLeft = document.createElement('div');
      this.quickSeekLeft.className = 'vjs-quick-seek-feedback vjs-seek-left';
      this.quickSeekLeft.innerHTML = `
        <div class="vjs-seek-content">
          ${brandIcon('prev')}
          <span class="vjs-seek-text">-5s</span>
        </div>
      `;
      playerEl.appendChild(this.quickSeekLeft);

      this.quickSeekRight = document.createElement('div');
      this.quickSeekRight.className = 'vjs-quick-seek-feedback vjs-seek-right';
      this.quickSeekRight.innerHTML = `
        <div class="vjs-seek-content">
          ${brandIcon('next')}
          <span class="vjs-seek-text">+5s</span>
        </div>
      `;
      playerEl.appendChild(this.quickSeekRight);

      // 7. 左右滑动快进/后退中央 HUD 浮层
      this.gestureHud = document.createElement('div');
      this.gestureHud.className = 'vjs-gesture-hud';
      this.gestureHud.innerHTML = `
        <div class="vjs-hud-icon-wrap">
          ${brandIcon('next', 'vjs-hud-forward')}
          ${brandIcon('prev', 'vjs-hud-backward')}
          <span class="vjs-hud-delta font-bold text-sm text-indigo-400 font-mono">+0s</span>
        </div>
        <div class="vjs-hud-time">00:00 / 00:00</div>
        <div class="vjs-hud-progress-bg">
          <div class="vjs-hud-progress-bar"></div>
        </div>
      `;
      playerEl.appendChild(this.gestureHud);
    }

    // 移动端手势核心引擎 (左右滑动快进后退 / 双击左退5s右进5s)
    setupGestureSystem() {
      const layer = this.gestureLayer;
      if (!layer) return;

      let touchStartX = 0;
      let touchStartY = 0;
      let gestureStartTime = 0;
      let gestureDuration = 0;
      let isSwiping = false;
      let isDetermined = false;
      let targetTime = 0;

      let lastTapTime = 0;
      let lastTapPos = { x: 0, y: 0 };
      let singleTapTimer = null;
      let preventTapUntil = 0;

      // 触摸开始
      layer.addEventListener('touchstart', (e) => {
        if (e.touches.length !== 1) return;
        const touch = e.touches[0];
        touchStartX = touch.clientX;
        touchStartY = touch.clientY;
        gestureStartTime = this.player.currentTime() || 0;
        gestureDuration = this.player.duration() || 0;
        isSwiping = false;
        isDetermined = false;
        targetTime = gestureStartTime;
      }, { passive: true });

      // 触摸滑动 (判定左右滑动手势)
      layer.addEventListener('touchmove', (e) => {
        if (e.touches.length !== 1) return;
        const touch = e.touches[0];
        const dx = touch.clientX - touchStartX;
        const dy = touch.clientY - touchStartY;

        if (!isDetermined) {
          if (Math.hypot(dx, dy) > 10) {
            isDetermined = true;
            if (Math.abs(dx) > Math.abs(dy)) {
              isSwiping = true;
              if (singleTapTimer) {
                clearTimeout(singleTapTimer);
                singleTapTimer = null;
              }
            } else {
              isSwiping = false;
            }
          }
        }

        if (isSwiping) {
          if (e.cancelable) e.preventDefault();

          const rect = layer.getBoundingClientRect();
          const width = rect.width || window.innerWidth || 360;
          const maxSeekRange = gestureDuration > 0 ? Math.min(gestureDuration, Math.max(90, gestureDuration * 0.15)) : 90;
          const deltaSec = (dx / width) * maxSeekRange;

          targetTime = Math.max(0, Math.min(gestureDuration, gestureStartTime + deltaSec));
          const diffSec = Math.round(targetTime - gestureStartTime);

          this.showGestureHud(targetTime, gestureDuration, diffSec);
        }
      }, { passive: false });

      // 触摸结束
      layer.addEventListener('touchend', (e) => {
        if (isSwiping) {
          preventTapUntil = Date.now() + 350;
          this.hideGestureHud();
          if (Math.abs(targetTime - gestureStartTime) > 0.5) {
            this.player.currentTime(targetTime);
            const sign = targetTime >= gestureStartTime ? '+' : '';
            const diff = Math.round(targetTime - gestureStartTime);
            this.showToast(`跳转至 ${this.formatTime(targetTime)} (${sign}${diff}s)`);
          }
          isSwiping = false;
          isDetermined = false;
          return;
        }

        if (Date.now() < preventTapUntil) return;

        const now = Date.now();
        const touch = e.changedTouches[0];
        const rect = layer.getBoundingClientRect();
        const tapX = touch.clientX - rect.left;
        const tapY = touch.clientY - rect.top;

        const timeDiff = now - lastTapTime;
        const dist = Math.hypot(tapX - lastTapPos.x, tapY - lastTapPos.y);

        if (timeDiff < 320 && dist < 45) {
          if (singleTapTimer) {
            clearTimeout(singleTapTimer);
            singleTapTimer = null;
          }
          lastTapTime = 0;

          const midX = rect.width / 2;
          if (tapX < midX) {
            this.handleQuickSeek(-5);
          } else {
            this.handleQuickSeek(5);
          }
        } else {
          lastTapTime = now;
          lastTapPos = { x: tapX, y: tapY };

          if (singleTapTimer) clearTimeout(singleTapTimer);
          singleTapTimer = setTimeout(() => {
            preventTapUntil = Date.now() + 400;
            if (this.routesMenuEl && this.routesMenuEl.classList.contains('show')) {
              this.closeRoutesMenu();
            } else if (this.drawerEl && this.drawerEl.classList.contains('open')) {
              this.closeEpisodesDrawer();
            } else {
              this.togglePlay();
              if (this.player.userActive()) {
                this.player.userActive(false);
              } else {
                this.player.userActive(true);
              }
            }
            singleTapTimer = null;
          }, 260);
        }
      });

      let mouseClickTimer = null;

      // 桌面端鼠标单击 (单击播放/暂停)
      layer.addEventListener('click', (e) => {
        if (Date.now() < preventTapUntil) return;

        if (this.routesMenuEl && this.routesMenuEl.classList.contains('show')) {
          this.closeRoutesMenu();
          return;
        }
        if (this.drawerEl && this.drawerEl.classList.contains('open')) {
          this.closeEpisodesDrawer();
          return;
        }

        // 双击过程中的第二次 click 事件不触发单击播放
        if (e.detail > 1) {
          if (mouseClickTimer) {
            clearTimeout(mouseClickTimer);
            mouseClickTimer = null;
          }
          return;
        }

        if (mouseClickTimer) clearTimeout(mouseClickTimer);
        mouseClickTimer = setTimeout(() => {
          this.togglePlay();
          mouseClickTimer = null;
        }, 220);
      });

      // 桌面端鼠标双击 (左双击 -5s, 右双击 +5s)
      layer.addEventListener('dblclick', (e) => {
        if (mouseClickTimer) {
          clearTimeout(mouseClickTimer);
          mouseClickTimer = null;
        }
        const rect = layer.getBoundingClientRect();
        const tapX = e.clientX - rect.left;
        const midX = rect.width / 2;
        if (tapX < midX) {
          this.handleQuickSeek(-5);
        } else {
          this.handleQuickSeek(5);
        }
      });
    }

    // 执行快捷快进/回退 (+5s / -5s)
    handleQuickSeek(offsetSec) {
      const cur = this.player.currentTime() || 0;
      const dur = this.player.duration() || 0;
      let target = cur + offsetSec;
      if (dur > 0) {
        target = Math.max(0, Math.min(dur, target));
      } else {
        target = Math.max(0, target);
      }

      this.player.currentTime(target);

      if (offsetSec < 0) {
        this.triggerQuickSeekAnim('left', '-5s');
        this.showToast('快退 5 秒');
      } else {
        this.triggerQuickSeekAnim('right', '+5s');
        this.showToast('快进 5 秒');
      }
    }

    // 触发双击扇形动效反馈
    triggerQuickSeekAnim(side, text) {
      const animEl = side === 'left' ? this.quickSeekLeft : this.quickSeekRight;
      if (!animEl) return;
      const textEl = animEl.querySelector('.vjs-seek-text');
      if (textEl) textEl.innerText = text;

      animEl.classList.remove('active');
      void animEl.offsetWidth;
      animEl.classList.add('active');

      const timerKey = `_seekTimer_${side}`;
      if (this[timerKey]) clearTimeout(this[timerKey]);
      this[timerKey] = setTimeout(() => {
        animEl.classList.remove('active');
      }, 600);
    }

    // 展示左右滑动 HUD
    showGestureHud(targetTime, totalDuration, diffSec) {
      if (!this.gestureHud) return;
      const forwardIcon = this.gestureHud.querySelector('.vjs-hud-forward');
      const backwardIcon = this.gestureHud.querySelector('.vjs-hud-backward');
      const deltaEl = this.gestureHud.querySelector('.vjs-hud-delta');
      const timeEl = this.gestureHud.querySelector('.vjs-hud-time');
      const barEl = this.gestureHud.querySelector('.vjs-hud-progress-bar');

      if (diffSec >= 0) {
        forwardIcon.style.display = 'block';
        backwardIcon.style.display = 'none';
        deltaEl.innerText = `+${diffSec}s`;
        deltaEl.style.color = '#818cf8';
      } else {
        forwardIcon.style.display = 'none';
        backwardIcon.style.display = 'block';
        deltaEl.innerText = `${diffSec}s`;
        deltaEl.style.color = '#38bdf8';
      }

      timeEl.innerText = `${this.formatTime(targetTime)} / ${this.formatTime(totalDuration)}`;

      let pct = 0;
      if (totalDuration > 0) {
        pct = Math.max(0, Math.min(100, (targetTime / totalDuration) * 100));
      }
      barEl.style.width = pct + '%';

      this.gestureHud.classList.add('show');
    }

    hideGestureHud() {
      if (this.gestureHud) {
        this.gestureHud.classList.remove('show');
      }
    }

    formatTime(seconds) {
      if (isNaN(seconds) || seconds < 0) seconds = 0;
      const s = Math.floor(seconds);
      const m = Math.floor(s / 60);
      const h = Math.floor(m / 60);
      const sec = s % 60;
      const min = m % 60;
      const ss = sec < 10 ? '0' + sec : '' + sec;
      const mm = min < 10 ? '0' + min : '' + min;
      if (h > 0) {
        const hh = h < 10 ? '0' + h : '' + h;
        return `${hh}:${mm}:${ss}`;
      }
      return `${mm}:${ss}`;
    }

    // 监听播放器容器尺寸自适应文案
    setupResponsiveObserver() {
      const updateLabels = () => this.updateBtnLabels();
      window.addEventListener('resize', updateLabels);
      if (window.ResizeObserver) {
        const ro = new ResizeObserver(() => updateLabels());
        const el = this.player ? this.player.el() : null;
        if (el) ro.observe(el);
      }
    }

    // 动态调整按钮文案 (移动端紧凑模式 vs 桌面端完整模式)
    updateBtnLabels() {
      const playerEl = this.player ? this.player.el() : null;
      const width = playerEl ? playerEl.clientWidth : window.innerWidth;
      const isCompact = width < 680;

      // 画面比例 (居中 / 16:9 / 4:3 / 铺满)
      if (this.btnRatio) {
        this.btnRatio.setAttribute('aria-label', `画面比例：${(ASPECT_MODES.find(m => m.key === this.aspectRatio) || ASPECT_MODES[0]).name}`);
        const textSpan = this.btnRatio.querySelector('.ratio-text');
        if (textSpan) {
          const mode = ASPECT_MODES.find(m => m.key === this.aspectRatio) || ASPECT_MODES[0];
          textSpan.innerText = isCompact ? mode.short : mode.label;
        }
      }

      // 连播开关
      if (this.btnAutoplay) {
        this.btnAutoplay.setAttribute('aria-pressed', String(this.isAutoplayNext));
        this.btnAutoplay.setAttribute('aria-label', this.isAutoplayNext ? '自动连播：已开启' : '自动连播：已关闭');
        const textSpan = this.btnAutoplay.querySelector('.autoplay-text');
        if (textSpan) {
          textSpan.innerText = isCompact
            ? (this.isAutoplayNext ? '连播' : '单集')
            : (this.isAutoplayNext ? '连播: 开' : '连播: 关');
        }
      }

      // 线路标签
      if (this.btnRoutes) {
        this.btnRoutes.setAttribute('aria-label', `切换线路：${this.routes[this.currentRouteIndex]?.server || this.currentRouteIndex + 1}`);
        const labelSpan = this.btnRoutes.querySelector('.route-label');
        if (labelSpan) {
          const cur = this.routes[this.currentRouteIndex];
          labelSpan.innerText = cur
            ? (isCompact ? `线${this.currentRouteIndex + 1}` : `线路 ${this.currentRouteIndex + 1}`)
            : '线路';
        }
      }
      if (this.player) this.player.trigger('blliisettingschange');
    }

    bindEvents() {
      // 视频播放结束触发自动连播与100%进度记录
      this.player.on('ended', () => {
        if (typeof this.options.onTimeUpdate === 'function') {
          const dur = this.player.duration() || 0;
          this.options.onTimeUpdate(dur, dur, 100);
        }

        if (!this.isAutoplayNext) return;

        if (this.currentEpisodeIndex + 1 < this.episodes.length) {
          const nextEp = this.episodes[this.currentEpisodeIndex + 1];
          this.startNextCountdown(nextEp);
        } else {
          this.showToast('🎉 本季全部剧集已播放完毕');
        }
      });

      // 监听播放暂停，立即同步保存一次最新时间
      this.player.on('pause', () => {
        if (typeof this.options.onTimeUpdate === 'function') {
          const cur = this.player.currentTime() || 0;
          const dur = this.player.duration() || 0;
          const pct = dur > 0 ? (cur / dur) * 100 : 0;
          this.options.onTimeUpdate(cur, dur, pct);
        }
      });

      // 监听播放进度更新 (节流约 1.5 秒更新一次)
      this.player.on('timeupdate', () => {
        const now = Date.now();
        if (now - this.lastTimeUpdateReport < 1500) return;
        this.lastTimeUpdateReport = now;

        const cur = this.player.currentTime() || 0;
        const dur = this.player.duration() || 0;
        if (typeof this.options.onTimeUpdate === 'function') {
          const pct = dur > 0 ? (cur / dur) * 100 : 0;
          this.options.onTimeUpdate(cur, dur, pct);
        }
      });

      // 视频元数据就绪时，再次确保居中渲染，并恢复上次播放进度 (断点续播)
      this.player.on('loadedmetadata', () => {
        this.applyAspectRatio(this.aspectRatio, false);
        if (this.pendingSeekTime && this.pendingSeekTime > 0) {
          const target = this.pendingSeekTime;
          this.pendingSeekTime = 0;
          const dur = this.player.duration() || 0;
          if (dur === 0 || target < dur - 5) {
            this.player.currentTime(target);
            this.showToast(`🕒 已恢复至上次观看进度: ${this.formatTime(target)}`);
          }
        }
      });

      // 键盘全局热键监听
      this._boundKeyDown = (e) => this.handleKeyDown(e);
      document.addEventListener('keydown', this._boundKeyDown);
    }

    // 键盘全局快捷键分发处理
    handleKeyDown(e) {
      if (this.settingsDialog?.open) return;
      // 忽略处于输入表单或富文本中的按键
      const activeEl = document.activeElement;
      const tag = activeEl ? activeEl.tagName.toLowerCase() : '';
      if (tag === 'input' || tag === 'textarea' || tag === 'select' || (activeEl && activeEl.isContentEditable)) {
        return;
      }

      // 如果有组合键 (Ctrl / Alt / Meta)，不拦截系统或浏览器原生快捷键
      if (e.ctrlKey || e.altKey || e.metaKey) {
        return;
      }

      const key = e.key;
      const code = e.code;

      // ESC 键：关闭选集抽屉、线路弹窗与连播倒计时
      if (key === 'Escape') {
        this.closeEpisodesDrawer();
        this.closeRoutesMenu();
        this.clearCountdown();
        return;
      }

      // 空格键：播放 / 暂停
      if (key === ' ' || code === 'Space') {
        e.preventDefault();
        this.togglePlay();
        return;
      }

      // 方向键 上：音量增加 10%
      if (key === 'ArrowUp') {
        e.preventDefault();
        this.adjustVolume(0.1);
        return;
      }

      // 方向键 下：音量减少 10%
      if (key === 'ArrowDown') {
        e.preventDefault();
        this.adjustVolume(-0.1);
        return;
      }

      // 方向键 左：快退 5 秒
      if (key === 'ArrowLeft') {
        e.preventDefault();
        this.seekRelative(-5);
        return;
      }

      // 方向键 右：快进 5 秒
      if (key === 'ArrowRight') {
        e.preventDefault();
        this.seekRelative(5);
        return;
      }

      // [ 键：上一集 (兼容英文 [ 与 中文输入法 【)
      if (key === '[' || key === '【' || code === 'BracketLeft') {
        e.preventDefault();
        this.playPrevEpisode();
        return;
      }

      // ] 键：下一集 (兼容英文 ] 与 中文输入法 】)
      if (key === ']' || key === '】' || code === 'BracketRight') {
        e.preventDefault();
        this.playNextEpisode();
        return;
      }

      // F 键：全屏切换
      if (key === 'f' || key === 'F') {
        e.preventDefault();
        this.toggleFullscreen();
        return;
      }

      // M 键：静音切换
      if (key === 'm' || key === 'M') {
        e.preventDefault();
        this.toggleMute();
        return;
      }
    }

    // 播放 / 暂停切换
    togglePlay() {
      if (!this.player) return;
      if (this.player.paused()) {
        this.player.play().catch(e => {
          console.log('Play handled:', e);
        });
        this.showToast('▶ 播放', 1200);
      } else {
        this.player.pause();
        this.showToast('⏸ 暂停', 1200);
      }
    }

    // 调节音量 (delta: +0.1 或 -0.1)
    adjustVolume(delta) {
      if (!this.player) return;
      if (this.player.muted() && delta > 0) {
        this.player.muted(false);
      }
      let currentVol = this.player.volume();
      if (typeof currentVol !== 'number' || isNaN(currentVol)) {
        currentVol = 1.0;
      }
      let newVol = Math.round((currentVol + delta) * 100) / 100;
      newVol = Math.max(0, Math.min(1, newVol));
      this.player.volume(newVol);

      if (newVol === 0) {
        this.player.muted(true);
      } else if (this.player.muted() && newVol > 0) {
        this.player.muted(false);
      }

      const pct = Math.round(newVol * 100);
      const icon = (pct === 0 || this.player.muted()) ? '🔇' : (pct < 50 ? '🔉' : '🔊');
      this.showToast(`${icon} 音量: ${pct}%`, 1200);
    }

    // 静音切换
    toggleMute() {
      if (!this.player) return;
      const isMuted = this.player.muted();
      this.player.muted(!isMuted);
      if (!isMuted) {
        this.showToast('🔇 已静音', 1200);
      } else {
        const pct = Math.round((this.player.volume() || 1) * 100);
        this.showToast(`🔊 取消静音 (${pct}%)`, 1200);
      }
    }

    // 相对快进 / 快退 (秒)
    seekRelative(seconds) {
      if (!this.player) return;
      const cur = this.player.currentTime() || 0;
      const dur = this.player.duration() || 0;
      let target = cur + seconds;
      if (dur > 0) {
        target = Math.max(0, Math.min(dur, target));
      } else {
        target = Math.max(0, target);
      }
      this.player.currentTime(target);

      if (seconds < 0) {
        this.triggerQuickSeekAnim('left', `${seconds}s`);
        const timeInfo = dur > 0 ? ` (${this.formatTime(target)} / ${this.formatTime(dur)})` : '';
        this.showToast(`⏪ 快退 ${Math.abs(seconds)} 秒${timeInfo}`, 1200);
      } else {
        this.triggerQuickSeekAnim('right', `+${seconds}s`);
        const timeInfo = dur > 0 ? ` (${this.formatTime(target)} / ${this.formatTime(dur)})` : '';
        this.showToast(`⏩ 快进 ${seconds} 秒${timeInfo}`, 1200);
      }
    }

    // 全屏切换
    toggleFullscreen() {
      if (!this.player) return;
      if (this.player.isFullscreen()) {
        this.player.exitFullscreen();
      } else {
        this.player.requestFullscreen();
      }
    }

    // 载入视频全部数据 (支持传入 initialTime 恢复进度)
    loadVideoData(videoRecord, initialRouteIndex = 0, initialEpIndex = 0, initialTime = 0) {
      this.currentVideo = videoRecord;
      this.routes = videoRecord.play_groups || [];
      this.currentRouteIndex = initialRouteIndex;
      this.currentEpisodeIndex = initialEpIndex;
      if (initialTime > 0) {
        this.pendingSeekTime = initialTime;
      }

      if (this.routes.length === 0) {
        this.showToast('当前视频无可用线路');
        return;
      }

      this.updateRoutesUI();
      this.playEpisode(this.currentRouteIndex, this.currentEpisodeIndex, initialTime);
    }

    // 播放指定线路与集数 (支持传入 initialTime 恢复进度，customToast 自定义提示)
    async playEpisode(routeIdx, epIdx, initialTime = 0, customToast = '') {
      if (!this.routes[routeIdx]) return;
      this.currentRouteIndex = routeIdx;
      this.episodes = this.routes[routeIdx].episodes || [];

      if (!this.episodes[epIdx]) {
        if (this.episodes.length > 0) {
          epIdx = 0;
        } else {
          this.showToast('该线路暂无集数');
          return;
        }
      }
      this.currentEpisodeIndex = epIdx;
      const targetEp = this.episodes[epIdx];

      if (initialTime > 0) {
        this.pendingSeekTime = initialTime;
      }

      this.clearCountdown();
      this.closeEpisodesDrawer();

      // 直连源站，在本机生成过滤后的列表；快速切集时取消旧请求。
      const generation = ++this.sourceGeneration;
      this.playlistAbort?.abort();
      this.playlistAbort = new AbortController();
      this.player.pause();
      let url = targetEp.url;
      let type = 'video/mp4';
      const oldResource = this.playlistResource;
      let resource = null;
      if (/\.m3u8(?:[?#]|$)/i.test(url) || (!/\.(?:mp4|webm|mkv|mov|avi)(?:[?#]|$)/i.test(url) && /hls|m3u8/i.test(this.routes[routeIdx].player_code || ''))) {
        type = 'application/x-mpegURL';
        if (this.options.cleanM3U8) {
          try {
            resource = await prepareClientPlaylist(url, { signal: this.playlistAbort.signal, options: this.options.cleanOptions });
            url = resource.url;
          } catch (error) {
            if (generation !== this.sourceGeneration || !this.player) return;
            console.warn('客户端 M3U8 过滤失败，使用原始播放地址', error);
          }
        }
      }
      if (generation !== this.sourceGeneration || !this.player) { resource?.dispose(); return; }
      this.resetPreview();
      this.playlistResource = resource;
      this.player.src({ src: url, type: type });
      oldResource?.dispose();
      this.player.play().catch(e => {
        console.log('Autoplay handled:', e);
      });

      // 更新按钮与抽屉显示
      this.updateRoutesUI();
      this.updateEpisodesDrawerUI();

      this.showToast(customToast || `正在播放: ${targetEp.name}`);

      // 触发外部回调
      if (typeof this.options.onEpisodeChange === 'function') {
        this.options.onEpisodeChange(this.currentRouteIndex, this.currentEpisodeIndex, targetEp);
      }
    }

    // 切换线路
    switchRoute(routeIdx) {
      if (routeIdx === this.currentRouteIndex || !this.routes[routeIdx]) return;
      this.currentRouteIndex = routeIdx;
      this.closeRoutesMenu();

      const newEpisodes = this.routes[routeIdx].episodes || [];
      let epIdx = this.currentEpisodeIndex;
      if (epIdx >= newEpisodes.length) epIdx = 0;

      this.playEpisode(this.currentRouteIndex, epIdx);

      if (typeof this.options.onRouteChange === 'function') {
        this.options.onRouteChange(this.currentRouteIndex);
      }
    }

    // 播放下一集
    playNextEpisode() {
      if (!this.episodes || this.episodes.length === 0) {
        this.showToast('暂无剧集信息', 1500);
        return;
      }
      if (this.currentEpisodeIndex + 1 < this.episodes.length) {
        const nextIdx = this.currentEpisodeIndex + 1;
        const nextEp = this.episodes[nextIdx];
        const title = nextEp ? nextEp.name : `第${nextIdx + 1}话`;
        this.playEpisode(this.currentRouteIndex, nextIdx, 0, `⏭ 下一集: ${title}`);
      } else {
        this.showToast('⚠️ 已经是最后一集了', 1500);
      }
    }

    // 播放上一集
    playPrevEpisode() {
      if (!this.episodes || this.episodes.length === 0) {
        this.showToast('暂无剧集信息', 1500);
        return;
      }
      if (this.currentEpisodeIndex > 0) {
        const prevIdx = this.currentEpisodeIndex - 1;
        const prevEp = this.episodes[prevIdx];
        const title = prevEp ? prevEp.name : `第${prevIdx + 1}话`;
        this.playEpisode(this.currentRouteIndex, prevIdx, 0, `⏮ 上一集: ${title}`);
      } else {
        this.showToast('⚠️ 已经是第一集了', 1500);
      }
    }

    // 启动下一集倒计时
    startNextCountdown(nextEp) {
      this.clearCountdown();
      this.countdownLeft = this.options.nextCountdownSec;

      this.countdownCard.querySelector('#countdown-ep-title').innerText = nextEp.name;
      this.countdownCard.querySelector('#countdown-num-text').innerText = this.countdownLeft;
      this.countdownCard.classList.add('show');

      this.countdownTimer = setInterval(() => {
        this.countdownLeft--;
        if (this.countdownLeft <= 0) {
          this.clearCountdown();
          this.playNextEpisode();
        } else {
          this.countdownCard.querySelector('#countdown-num-text').innerText = this.countdownLeft;
        }
      }, 1000);
    }

    clearCountdown() {
      if (this.countdownTimer) {
        clearInterval(this.countdownTimer);
        this.countdownTimer = null;
      }
      if (this.countdownCard) {
        this.countdownCard.classList.remove('show');
      }
    }

    // 自动播放下一集开关
    toggleAutoplayNext(forceVal) {
      this.isAutoplayNext = typeof forceVal === 'boolean' ? forceVal : !this.isAutoplayNext;

      if (this.isAutoplayNext) {
        this.btnAutoplay.classList.add('active');
        this.showToast('自动连播下一集: 已开启');
      } else {
        this.btnAutoplay.classList.remove('active');
        this.clearCountdown();
        this.showToast('自动连播下一集: 已关闭');
      }

      this.updateBtnLabels();
      localStorage.setItem('vplayer_autoplay_next', this.isAutoplayNext ? 'true' : 'false');
    }

    // 线路菜单与选集抽屉控制
    toggleRoutesMenu() {
      if (this.routesMenuEl.classList.contains('show')) {
        this.closeRoutesMenu();
      } else {
        this.openRoutesMenu();
      }
    }

    openRoutesMenu() {
      this.closeEpisodesDrawer();
      this.routesMenuEl.innerHTML = this.routes.map((r, idx) => `
        <div class="vjs-route-item ${idx === this.currentRouteIndex ? 'selected' : ''}" data-idx="${idx}">
          <span>线路 ${idx + 1}</span>
          <span class="text-[10px] opacity-75 uppercase font-mono">${r.player_code || 'm3u8'}</span>
        </div>
      `).join('');

      this.routesMenuEl.querySelectorAll('.vjs-route-item').forEach(item => {
        item.onclick = (e) => {
          e.stopPropagation();
          const idx = parseInt(item.getAttribute('data-idx'));
          this.switchRoute(idx);
        };
      });

      this.routesMenuEl.classList.add('show');
    }

    closeRoutesMenu() {
      if (this.routesMenuEl) this.routesMenuEl.classList.remove('show');
    }

    toggleEpisodesDrawer() {
      if (this.drawerEl.classList.contains('open')) {
        this.closeEpisodesDrawer();
      } else {
        this.openEpisodesDrawer();
      }
    }

    openEpisodesDrawer() {
      this.closeRoutesMenu();
      this.updateEpisodesDrawerUI();
      this.drawerEl.classList.add('open');
    }

    closeEpisodesDrawer() {
      if (this.drawerEl) this.drawerEl.classList.remove('open');
    }

    updateRoutesUI() {
      this.updateBtnLabels();
    }

    updateEpisodesDrawerUI() {
      if (!this.drawerEl) return;
      const listEl = this.drawerEl.querySelector('#drawer-episodes-list');
      const titleEl = this.drawerEl.querySelector('#drawer-video-title');

      if (this.currentVideo) {
        titleEl.innerText = `${this.currentVideo.name} (共 ${this.episodes.length} 集)`;
      }

      listEl.innerHTML = this.episodes.map((ep, i) => `
        <button class="vjs-drawer-ep-btn ${i === this.currentEpisodeIndex ? 'active' : ''}" data-ep="${i}" title="${ep.name}">
          ${ep.name}
        </button>
      `).join('');

      listEl.querySelectorAll('.vjs-drawer-ep-btn').forEach(btn => {
        btn.onclick = (e) => {
          e.stopPropagation();
          const ep = parseInt(btn.getAttribute('data-ep'));
          this.playEpisode(this.currentRouteIndex, ep);
        };
      });
    }

    showToast(msg, duration = 1500) {
      if (!this.toastEl) return;
      this.toastEl.innerHTML = brandIcon('sparkles');
      const label = document.createElement('span');
      label.textContent = msg.replace(/[\p{Extended_Pictographic}\uFE0F]/gu, '').trim();
      this.toastEl.appendChild(label);
      this.toastEl.classList.add('show');
      if (this.toastTimer) clearTimeout(this.toastTimer);
      this.toastTimer = setTimeout(() => {
        this.toastEl.classList.remove('show');
      }, duration);
    }

    getCurrentTime() {
      return this.player ? (this.player.currentTime() || 0) : 0;
    }

    getDuration() {
      return this.player ? (this.player.duration() || 0) : 0;
    }

    seekTo(seconds) {
      if (this.player && typeof seconds === 'number') {
        this.player.currentTime(seconds);
      }
    }

    setupBrowserFeatures() {
      ensureBrowserFeatureStyles();
      const root = this.player.el();
      const syncIcons = () => {
        root.querySelector('.vjs-play-control .bllii-player-icon use')?.setAttribute('href', `#bllii-${this.player.paused() ? 'play' : 'pause'}`);
        root.querySelector('.vjs-mute-control .bllii-player-icon use')?.setAttribute('href', `#bllii-${this.player.muted() || !this.player.volume() ? 'muted' : 'volume'}`);
        root.querySelector('.vjs-playback-rate > button')?.setAttribute('aria-label', `播放速度：${this.player.playbackRate()} 倍`);
      };
      this.player.on(['play', 'pause', 'volumechange', 'ratechange'], syncIcons);
      syncIcons();
      const playProgress = root.querySelector('.vjs-play-progress');
      playProgress?.insertAdjacentHTML('beforeend', `<span class="bllii-seek-mascot">${brandIcon('scrubber')}</span>`);
      this.pictureSettings = { brightness: 100, contrast: 100, saturation: 100, gray: 0 };
      try {
        const saved = JSON.parse(localStorage.getItem('bllii_picture_settings') || 'null');
        if (saved) Object.keys(this.pictureSettings).forEach(key => {
          const [min, max] = { brightness: [50, 150], contrast: [50, 150], saturation: [0, 200], gray: [0, 1] }[key];
          if (Number.isFinite(saved[key])) this.pictureSettings[key] = Math.max(min, Math.min(max, saved[key]));
        });
      } catch {}
      this.soundMode = 'original';
      this.applyPictureSettings();
      this.createSettingsPanel();
      root.addEventListener('contextmenu', event => {
        if (event.target.closest('input, select, textarea, .bllii-settings-panel')) return;
        event.preventDefault();
        this.openSettings(event);
      });
      this.setupFramePreview();
      this.player.on('dispose', () => this.disposeBrowserFeatures());
    }

    applyPictureSettings() {
      const settings = this.pictureSettings;
      const isOriginal = settings.brightness === 100 && settings.contrast === 100 && settings.saturation === 100 && !settings.gray;
      this.player.el().style.setProperty('--bllii-picture-filter', isOriginal ? 'none' : `brightness(${settings.brightness / 100}) contrast(${settings.contrast / 100}) saturate(${settings.saturation / 100}) grayscale(${settings.gray})`);
      try { localStorage.setItem('bllii_picture_settings', JSON.stringify(settings)); } catch {}
    }

    createSettingsPanel() {
      const dialog = document.createElement('dialog');
      dialog.className = 'bllii-settings-panel';
      dialog.setAttribute('aria-label', '放映设置');
      dialog.innerHTML = `
        <header><strong>${brandIcon('settings')} 放映设置</strong><button class="bllii-panel-close" aria-label="关闭设置">${brandIcon('close')}</button></header>
        <div class="bllii-settings-tabs" role="tablist" aria-label="设置类型">
          <button type="button" role="tab" data-settings-tab="picture" aria-selected="true">画面</button>
          <button type="button" role="tab" data-settings-tab="sound" aria-selected="false">声音</button>
        </div>
        <div class="bllii-settings-body" data-settings-pane="picture" role="tabpanel">
          <label class="bllii-setting-row"><span>滤镜</span><select data-picture-preset><option value="original">原始画面</option><option value="soft">柔和</option><option value="bright">明亮</option><option value="mono">黑白</option><option value="custom">自定义</option></select></label>
          ${[['brightness', '亮度', 50, 150], ['contrast', '对比度', 50, 150], ['saturation', '饱和度', 0, 200]].map(([key, label, min, max]) => `<label class="bllii-setting-row"><span>${label}<output data-picture-value="${key}">100%</output></span><input type="range" data-picture-slider="${key}" min="${min}" max="${max}" value="100" aria-label="${label}"></label>`).join('')}
        </div>
        <div class="bllii-settings-body" data-settings-pane="sound" role="tabpanel" hidden>
          <label class="bllii-setting-row"><span>音效</span><select data-sound-mode><option value="original">原声</option><option value="dialogue">对白清晰</option><option value="bass">低音</option><option value="night">夜间</option></select></label>
          <p class="bllii-sound-state" data-sound-state aria-live="polite"></p>
        </div>
        <footer><button type="button" data-settings-reset>${brandIcon('history')} 恢复默认</button><small>bllii / YOUR SCREEN</small></footer>
      `;
      this.settingsDialog = dialog;
      this.player.el().appendChild(dialog);
      dialog.querySelector('.bllii-panel-close').onclick = () => dialog.close();
      dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
      const tabs = [...dialog.querySelectorAll('[data-settings-tab]')];
      const selectTab = tab => {
        tabs.forEach(button => {
          const active = button === tab;
          button.setAttribute('aria-selected', String(active));
          button.tabIndex = active ? 0 : -1;
        });
        dialog.querySelectorAll('[data-settings-pane]').forEach(pane => pane.hidden = pane.dataset.settingsPane !== tab.dataset.settingsTab);
      };
      tabs.forEach((tab, i) => {
        tab.tabIndex = i ? -1 : 0;
        tab.onclick = () => selectTab(tab);
        tab.onkeydown = event => {
          if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
          event.preventDefault();
          const next = tabs[event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (i + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length];
          selectTab(next); next.focus();
        };
      });
      dialog.querySelectorAll('[data-picture-slider]').forEach(slider => slider.oninput = () => {
        this.pictureSettings[slider.dataset.pictureSlider] = Number(slider.value);
        dialog.querySelector('[data-picture-preset]').value = 'custom';
        this.applyPictureSettings(); this.syncPicturePanel();
      });
      dialog.querySelector('[data-picture-preset]').onchange = event => {
        const presets = {
          original: { brightness: 100, contrast: 100, saturation: 100, gray: 0 },
          soft: { brightness: 102, contrast: 92, saturation: 90, gray: 0 },
          bright: { brightness: 112, contrast: 105, saturation: 108, gray: 0 },
          mono: { brightness: 100, contrast: 105, saturation: 100, gray: 1 },
        };
        if (presets[event.target.value]) this.pictureSettings = { ...presets[event.target.value] };
        this.applyPictureSettings(); this.syncPicturePanel();
      };
      dialog.querySelector('[data-sound-mode]').onchange = event => this.setSoundMode(event.target.value);
      dialog.querySelector('[data-settings-reset]').onclick = () => {
        this.pictureSettings = { brightness: 100, contrast: 100, saturation: 100, gray: 0 };
        dialog.querySelector('[data-picture-preset]').value = 'original';
        this.applyPictureSettings(); this.syncPicturePanel(); this.setSoundMode('original');
      };
      const original = Object.entries(this.pictureSettings).every(([key, value]) => value === (key === 'gray' ? 0 : 100));
      dialog.querySelector('[data-picture-preset]').value = original ? 'original' : 'custom';
      this.syncPicturePanel();
    }

    syncPicturePanel() {
      this.settingsDialog.querySelectorAll('[data-picture-slider]').forEach(slider => {
        slider.value = this.pictureSettings[slider.dataset.pictureSlider];
        this.settingsDialog.querySelector(`[data-picture-value="${slider.dataset.pictureSlider}"]`).textContent = `${slider.value}%`;
      });
    }

    openSettings(event) {
      if (!this.settingsDialog || this.settingsDialog.open) return;
      this.closeEpisodesDrawer(); this.closeRoutesMenu();
      const selector = this.settingsDialog.querySelector('[data-sound-mode]');
      const supported = this.canProcessAudio();
      selector.disabled = !supported;
      this.settingsDialog.querySelector('[data-sound-state]').textContent = supported ? (this.soundMode === 'original' ? '原声' : selector.selectedOptions[0].textContent) : '当前线路不支持音效，保留原声';
      this.btnSettings?.focus({ preventScroll: true });
      this.settingsDialog.showModal();
      if (event && window.innerWidth > 600) {
        const bounds = this.settingsDialog.getBoundingClientRect();
        this.settingsDialog.style.margin = '0';
        this.settingsDialog.style.inset = 'auto';
        this.settingsDialog.style.left = `${Math.max(12, Math.min(event.clientX, innerWidth - bounds.width - 12))}px`;
        this.settingsDialog.style.top = `${Math.max(12, Math.min(event.clientY, innerHeight - bounds.height - 12))}px`;
      } else {
        this.settingsDialog.style.margin = 'auto'; this.settingsDialog.style.inset = '0';
      }
    }

    canProcessAudio() {
      if (!(window.AudioContext || window.webkitAudioContext)) return false;
      const video = this.player.el().querySelector('video.vjs-tech');
      if (!video?.currentSrc || video.readyState < 1) return false;
      const local = url => { try { return /^(blob:|data:)/.test(url) || new URL(url, location.href).origin === location.origin; } catch { return false; } };
      // A MediaElementAudioSource cannot be detached. Keep every episode/route safe for future switches.
      const sources = this.routes.flatMap(route => route.episodes || []);
      return (local(video.currentSrc) || !!video.crossOrigin) && sources.every(episode => local(episode.url) || /\.m3u8(?:\?|$)/i.test(episode.url) && /^blob:/.test(video.currentSrc));
    }

    async setSoundMode(mode) {
      if (!['original', 'dialogue', 'bass', 'night'].includes(mode)) return;
      const state = this.settingsDialog.querySelector('[data-sound-state]');
      const selector = this.settingsDialog.querySelector('[data-sound-mode]');
      try {
        if (mode !== 'original' && !this.canProcessAudio()) throw new Error('当前线路不支持音效，保留原声');
        if (mode !== 'original' && !this.audioContext) {
          const Context = window.AudioContext || window.webkitAudioContext;
          const context = new Context();
          await context.resume();
          let source;
          try { source = context.createMediaElementSource(this.player.el().querySelector('video.vjs-tech')); }
          catch (error) { await context.close(); throw error; }
          const low = context.createBiquadFilter(); low.type = 'lowshelf'; low.frequency.value = 180;
          const voice = context.createBiquadFilter(); voice.type = 'peaking'; voice.frequency.value = 2400; voice.Q.value = .8;
          const compressor = context.createDynamicsCompressor();
          const output = context.createGain();
          source.connect(low); low.connect(voice); voice.connect(compressor); compressor.connect(output); output.connect(context.destination);
          this.audioContext = context; this.audioNodes = { source, low, voice, compressor, output };
          this.player.on('play', () => this.audioContext?.resume().catch(() => {}));
        }
        if (this.audioContext) {
          await this.audioContext.resume();
          const { low, voice, compressor, output } = this.audioNodes;
          const time = this.audioContext.currentTime;
          low.gain.setTargetAtTime(mode === 'bass' ? 6 : mode === 'dialogue' ? -3 : 0, time, .05);
          voice.gain.setTargetAtTime(mode === 'dialogue' ? 4 : 0, time, .05);
          compressor.threshold.setTargetAtTime(mode === 'night' ? -32 : 0, time, .05);
          compressor.ratio.setTargetAtTime(mode === 'night' ? 8 : 1, time, .05);
          compressor.knee.setTargetAtTime(mode === 'night' ? 24 : 0, time, .05);
          output.gain.setTargetAtTime(mode === 'night' ? 1.25 : 1, time, .05);
        }
        this.soundMode = mode; selector.value = mode;
        state.textContent = selector.selectedOptions[0].textContent;
      } catch (error) {
        selector.value = this.soundMode;
        state.textContent = error.message || '音效暂不可用，保留原声';
      }
    }

    setupFramePreview() {
      const root = this.player.el();
      const progress = root.querySelector('.vjs-progress-control');
      if (!progress) return;
      const popup = document.createElement('div');
      popup.className = 'bllii-frame-preview'; popup.hidden = true;
      popup.innerHTML = `<div class="bllii-frame-preview__media"><div class="bllii-frame-preview__state">${brandIcon('scrubber')}<span data-preview-state>正在取帧</span></div></div><time class="bllii-frame-preview__time"></time>`;
      this.previewPopup = popup;
      root.appendChild(popup);
      progress.addEventListener('pointermove', event => {
        const duration = this.player.duration();
        if (event.pointerType === 'touch' || !Number.isFinite(duration) || duration <= 0 || this.settingsDialog?.open) return;
        const track = root.querySelector('.vjs-progress-holder').getBoundingClientRect();
        const fraction = Math.max(0, Math.min(1, (event.clientX - track.left) / track.width));
        this.previewTarget = Math.min(duration - .05, duration * fraction);
        popup.hidden = false;
        popup.style.left = `${Math.max(8, Math.min(event.clientX - root.getBoundingClientRect().left - popup.offsetWidth / 2, root.clientWidth - popup.offsetWidth - 8))}px`;
        popup.querySelector('time').textContent = this.formatTime(this.previewTarget);
        popup.classList.remove('is-ready');
        clearTimeout(this.previewDebounce);
        this.previewDebounce = setTimeout(() => this.seekPreviewFrame(), 180);
      });
      progress.addEventListener('pointerleave', () => { popup.hidden = true; clearTimeout(this.previewDebounce); });
      this.player.on('loadstart', () => this.resetPreview());
    }

    seekPreviewFrame() {
      const source = this.player.currentSource();
      if (!source?.src || this.previewPopup.hidden || this.previewFailed) return;
      if (!this.previewPlayer) {
        const video = document.createElement('video');
        video.className = 'video-js bllii-frame-player'; video.muted = true;
        video.setAttribute('playsinline', ''); video.tabIndex = -1; video.setAttribute('aria-hidden', 'true');
        this.previewPopup.querySelector('.bllii-frame-preview__media').prepend(video);
        const player = videojs(video, { controls: false, autoplay: false, preload: 'auto', muted: true, fluid: false, html5: { vhs: { overrideNative: true } } });
        this.previewPlayer = player;
        player.on('loadedmetadata', () => this.seekPreviewFrame());
        const show = () => {
          if (this.previewPlayer !== player || player.readyState() < 2) return;
          if (Math.abs(player.currentTime() - this.previewTarget) > .3) { this.seekPreviewFrame(); return; }
          clearTimeout(this.previewWatchdog);
          this.previewPopup.classList.add('is-ready');
        };
        player.on(['seeked', 'loadeddata'], show);
        player.on('error', () => this.failPreview());
        player.src(source);
      }
      if (this.previewPlayer.readyState() >= 1) {
        const duration = this.previewPlayer.duration();
        const target = Number.isFinite(duration) ? Math.min(this.previewTarget, Math.max(0, duration - .05)) : this.previewTarget;
        if (Math.abs(this.previewPlayer.currentTime() - target) < .15 && this.previewPlayer.readyState() >= 2) {
          clearTimeout(this.previewWatchdog);
          this.previewPopup.classList.add('is-ready');
          return;
        }
        this.previewPlayer.currentTime(target);
      }
      clearTimeout(this.previewWatchdog);
      this.previewWatchdog = setTimeout(() => this.failPreview(), 6000);
    }

    failPreview() {
      this.previewFailed = true;
      this.previewPopup?.classList.remove('is-ready');
      const state = this.previewPopup?.querySelector('[data-preview-state]');
      if (state) state.textContent = '预览暂不可用';
      if (this.previewPlayer) { this.previewPlayer.dispose(); this.previewPlayer = null; }
      clearTimeout(this.previewWatchdog);
    }

    resetPreview() {
      clearTimeout(this.previewDebounce); clearTimeout(this.previewWatchdog);
      if (this.previewPlayer) { this.previewPlayer.dispose(); this.previewPlayer = null; }
      this.previewFailed = false;
      if (this.previewPopup) {
        this.previewPopup.hidden = true;
        this.previewPopup.classList.remove('is-ready');
        this.previewPopup.querySelector('[data-preview-state]').textContent = '正在取帧';
      }
    }

    disposeBrowserFeatures() {
      ++this.sourceGeneration;
      this.playlistAbort?.abort();
      this.playlistResource?.dispose();
      this.playlistResource = null;
      this.resetPreview();
      this.settingsDialog?.close();
      this.settingsDialog?.remove();
      if (this.audioNodes) Object.values(this.audioNodes).forEach(node => node.disconnect());
      this.audioContext?.close().catch(() => {});
      this.audioContext = null;
    }

    destroy() {
      this.clearCountdown();
      if (this._boundKeyDown) {
        document.removeEventListener('keydown', this._boundKeyDown);
        this._boundKeyDown = null;
      }
      if (this.player) {
        this.player.dispose();
        this.player = null;
      }
    }
  }

  // 暴露通用格式化时间工具
  ModernVideoPlayer.formatTime = function(seconds) {
    if (!seconds || isNaN(seconds)) return '00:00';
    const s = Math.floor(seconds);
    const m = Math.floor(s / 60);
    const h = Math.floor(m / 60);
    const sec = s % 60;
    const min = m % 60;
    const ss = sec < 10 ? '0' + sec : '' + sec;
    const mm = min < 10 ? '0' + min : '' + min;
    if (h > 0) {
      const hh = h < 10 ? '0' + h : '' + h;
      return `${hh}:${mm}:${ss}`;
    }
    return `${mm}:${ss}`;
  };

  // 挂载全局
  ModernVideoPlayer.cleanPlaylist = cleanPlaylist;
  ModernVideoPlayer.prepareClientPlaylist = prepareClientPlaylist;
  window.ModernVideoPlayer = ModernVideoPlayer;

})(window);
