/**
 * 极光现代化 Video.js 流媒体播放器内核 (Aurora Modern Video.js Player Engine)
 * 特性：
 * 1. 深度适配 m3u8 (HLS) / mp4 多流媒体切片
 * 2. 画质超清增强引擎 (卷积锐化矩阵 + 动态对比色彩算法，支持热开关与状态持久化)
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

  // 画面比例模式配置
  const ASPECT_MODES = [
    { key: 'auto', name: '居中自适应', label: '比例: 居中', short: '居中' },
    { key: '16:9', name: '16:9 宽屏', label: '比例: 16:9', short: '16:9' },
    { key: '4:3', name: '4:3 经典', label: '比例: 4:3', short: '4:3' },
    { key: 'fill', name: '画面铺满', label: '比例: 铺满', short: '铺满' },
  ];

  // 注入全站 SVG 锐化卷积滤镜 (提升视频边缘细节与微高频纹理)
  function ensureSvgFilter() {
    if (document.getElementById('vplayer-svg-filters')) return;
    const svgWrap = document.createElement('div');
    svgWrap.id = 'vplayer-svg-filters';
    svgWrap.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden;pointer-events:none;';
    svgWrap.innerHTML = `
      <svg xmlns="http://www.w3.org/2000/svg">
        <filter id="vplayer-sharpen-filter">
          <feConvolveMatrix order="3" preserveAlpha="true" kernelMatrix="
             0   -0.45    0
           -0.45  2.8   -0.45
             0   -0.45    0"/>
        </filter>
      </svg>
    `;
    document.body.appendChild(svgWrap);
  }

  // 注入播放器控制条高质感现代样式、比例居中与手势样式
  function ensurePlayerStyles() {
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

      /* 画质超清增强启用状态样式 */
      .vjs-modern-skin.vjs-enhanced .vjs-tech {
        filter: contrast(1.08) saturate(1.15) brightness(1.02) url(#vplayer-sharpen-filter) !important;
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
      .vjs-btn-enhance.active {
        background: linear-gradient(135deg, rgba(99, 102, 241, 0.85), rgba(168, 85, 247, 0.85)) !important;
        border-color: #818cf8 !important;
        color: #fff !important;
        box-shadow: 0 0 10px rgba(129, 140, 248, 0.4);
      }
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
        transform: translateX(100%);
        transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1);
        box-shadow: -10px 0 25px rgba(0,0,0,0.6);
      }
      .vjs-episodes-drawer.open {
        transform: translateX(0);
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
    document.head.appendChild(style);
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
        enhanceDefault: true,
        autoplayNextDefault: true,
        nextCountdownSec: 3,
        onEpisodeChange: null,
        onRouteChange: null,
        onTimeUpdate: null,
        initialTime: 0,
        cleanM3U8: true, // 默认开启智能切片广告过滤
        cleanProxyUrl: '/api/m3u8/clean', // 后端清洗代理地址
      }, options);

      this.player = null;
      this.currentVideo = null;
      this.currentRouteIndex = 0;
      this.currentEpisodeIndex = 0;
      this.routes = [];
      this.episodes = [];
      this.pendingSeekTime = this.options.initialTime || 0;
      this.lastTimeUpdateReport = 0;
      
      // 读取本地持久化设置
      const savedEnhance = localStorage.getItem('vplayer_enhance_enabled');
      this.isEnhanced = savedEnhance !== null ? savedEnhance === 'true' : this.options.enhanceDefault;

      const savedAutoplay = localStorage.getItem('vplayer_autoplay_next');
      this.isAutoplayNext = savedAutoplay !== null ? savedAutoplay === 'true' : this.options.autoplayNextDefault;

      // 画面比例模式 (默认 auto 居中自适应, 支持 16:9, 4:3, fill)
      this.aspectRatio = localStorage.getItem('vplayer_aspect_ratio') || 'auto';

      this.countdownTimer = null;
      this.countdownLeft = 0;

      ensureSvgFilter();
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
        if (this.isEnhanced) {
          playerEl.classList.add('vjs-enhanced');
        }

        // 应用比例模式 (16:9, 4:3 或 默认居中)
        this.applyAspectRatio(this.aspectRatio, false);

        this.injectCustomControls();
        this.injectOverlays();
        this.setupGestureSystem();
        this.setupResponsiveObserver();
        this.bindEvents();
      });
    }

    // 在 ControlBar 注入画面比例、画质、线路、选集、自动连播
    injectCustomControls() {
      const controlBar = this.player.getChild('controlBar');
      if (!controlBar) return;
      const cbEl = controlBar.el();

      // 1. 画质增强按钮
      this.btnEnhance = document.createElement('button');
      this.btnEnhance.type = 'button';
      this.btnEnhance.className = `vjs-custom-btn vjs-btn-enhance ${this.isEnhanced ? 'active' : ''}`;
      this.btnEnhance.title = '超清画质增强 (对比度/锐化/高动态色彩优化)';
      this.btnEnhance.innerHTML = `
        <svg class="w-3.5 h-3.5 mr-1" fill="currentColor" viewBox="0 0 20 20">
          <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z"/>
        </svg>
        <span class="enhance-text">画质增强: 开</span>
      `;
      this.btnEnhance.onclick = (e) => {
        e.stopPropagation();
        this.toggleEnhance();
      };

      // 2. 画面比例切换按钮 (居中自适应 / 16:9 / 4:3 / 铺满)
      this.btnRatio = document.createElement('button');
      this.btnRatio.type = 'button';
      this.btnRatio.className = `vjs-custom-btn vjs-btn-ratio ${this.aspectRatio !== 'auto' ? 'active' : ''}`;
      this.btnRatio.title = '画面比例与尺寸 (居中自适应 / 16:9 / 4:3 / 铺满)';
      this.btnRatio.innerHTML = `
        <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-5h-4m4 0v4m0-4l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"/>
        </svg>
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
        <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"/>
        </svg>
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
        <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16"/>
        </svg>
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
        <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
        </svg>
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
        cbEl.insertBefore(this.btnEnhance, targetAnchor);
        cbEl.insertBefore(this.btnRatio, targetAnchor);
        cbEl.insertBefore(this.btnRoutes, targetAnchor);
        cbEl.insertBefore(this.btnEpisodes, targetAnchor);
        cbEl.insertBefore(this.btnAutoplay, targetAnchor);
      } else {
        cbEl.appendChild(this.btnEnhance);
        cbEl.appendChild(this.btnRatio);
        cbEl.appendChild(this.btnRoutes);
        cbEl.appendChild(this.btnEpisodes);
        cbEl.appendChild(this.btnAutoplay);
      }

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
            <svg class="w-4 h-4 text-indigo-400" fill="currentColor" viewBox="0 0 20 20">
              <path d="M7 3a1 1 0 000 2h6a1 1 0 100-2H7zM4 7a1 1 0 011-1h10a1 1 0 110 2H5a1 1 0 01-1-1zM2 11a2 2 0 012-2h12a2 2 0 012 2v4a2 2 0 01-2 2H4a2 2 0 01-2-2v-4z"/>
            </svg>
            <span id="drawer-video-title">剧集选集</span>
          </div>
          <button class="vjs-drawer-close" title="关闭选集">&times;</button>
        </div>
        <div class="vjs-drawer-body" id="drawer-episodes-list"></div>
      `;
      this.drawerEl.querySelector('.vjs-drawer-close').onclick = () => this.closeEpisodesDrawer();
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
          <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M12.066 11.2a1 1 0 000 1.6l5.334 4A1 1 0 0019 16V8a1 1 0 00-1.6-.8l-5.334 4zM4.066 11.2a1 1 0 000 1.6l5.334 4A1 1 0 0011 16V8a1 1 0 00-1.6-.8l-5.334 4z"/>
          </svg>
          <span class="vjs-seek-text">-5s</span>
        </div>
      `;
      playerEl.appendChild(this.quickSeekLeft);

      this.quickSeekRight = document.createElement('div');
      this.quickSeekRight.className = 'vjs-quick-seek-feedback vjs-seek-right';
      this.quickSeekRight.innerHTML = `
        <div class="vjs-seek-content">
          <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M11.934 12.8a1 1 0 000-1.6l-5.334-4A1 1 0 005 8v8a1 1 0 001.6.8l5.334-4zM19.934 12.8a1 1 0 000-1.6l-5.334-4A1 1 0 0013 8v8a1 1 0 001.6.8l5.334-4z"/>
          </svg>
          <span class="vjs-seek-text">+5s</span>
        </div>
      `;
      playerEl.appendChild(this.quickSeekRight);

      // 7. 左右滑动快进/后退中央 HUD 浮层
      this.gestureHud = document.createElement('div');
      this.gestureHud.className = 'vjs-gesture-hud';
      this.gestureHud.innerHTML = `
        <div class="vjs-hud-icon-wrap">
          <svg class="vjs-hud-forward w-7 h-7" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M11.934 12.8a1 1 0 000-1.6l-5.334-4A1 1 0 005 8v8a1 1 0 001.6.8l5.334-4zM19.934 12.8a1 1 0 000-1.6l-5.334-4A1 1 0 0013 8v8a1 1 0 001.6.8l5.334-4z"/>
          </svg>
          <svg class="vjs-hud-backward w-7 h-7" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M12.066 11.2a1 1 0 000 1.6l5.334 4A1 1 0 0019 16V8a1 1 0 00-1.6-.8l-5.334 4zM4.066 11.2a1 1 0 000 1.6l5.334 4A1 1 0 0011 16V8a1 1 0 00-1.6-.8l-5.334 4z"/>
          </svg>
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

      // 画质增强
      if (this.btnEnhance) {
        const textSpan = this.btnEnhance.querySelector('.enhance-text');
        if (textSpan) {
          textSpan.innerText = isCompact
            ? (this.isEnhanced ? '超清' : '原画')
            : (this.isEnhanced ? '画质增强: 开' : '画质增强: 关');
        }
      }

      // 画面比例 (居中 / 16:9 / 4:3 / 铺满)
      if (this.btnRatio) {
        const textSpan = this.btnRatio.querySelector('.ratio-text');
        if (textSpan) {
          const mode = ASPECT_MODES.find(m => m.key === this.aspectRatio) || ASPECT_MODES[0];
          textSpan.innerText = isCompact ? mode.short : mode.label;
        }
      }

      // 连播开关
      if (this.btnAutoplay) {
        const textSpan = this.btnAutoplay.querySelector('.autoplay-text');
        if (textSpan) {
          textSpan.innerText = isCompact
            ? (this.isAutoplayNext ? '连播' : '单集')
            : (this.isAutoplayNext ? '连播: 开' : '连播: 关');
        }
      }

      // 线路标签
      if (this.btnRoutes) {
        const labelSpan = this.btnRoutes.querySelector('.route-label');
        if (labelSpan) {
          const cur = this.routes[this.currentRouteIndex];
          labelSpan.innerText = cur
            ? (isCompact ? `线${this.currentRouteIndex + 1}` : `线路 ${this.currentRouteIndex + 1}`)
            : '线路';
        }
      }
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
    playEpisode(routeIdx, epIdx, initialTime = 0, customToast = '') {
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

      // 更新播放地址
      let url = targetEp.url;
      let type = 'video/mp4';
      if (url.includes('.m3u8')) {
        type = 'application/x-mpegURL';
        if (this.options.cleanM3U8 && this.options.cleanProxyUrl && !url.includes(this.options.cleanProxyUrl)) {
          url = `${this.options.cleanProxyUrl}?url=${encodeURIComponent(url)}`;
        }
      }

      this.player.src({ src: url, type: type });
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

    // 画质超清增强开关
    toggleEnhance(forceVal) {
      this.isEnhanced = typeof forceVal === 'boolean' ? forceVal : !this.isEnhanced;
      const playerEl = this.player.el();

      if (this.isEnhanced) {
        playerEl.classList.add('vjs-enhanced');
        this.btnEnhance.classList.add('active');
        this.showToast('✨ 超清画质增强已开启 (边缘锐化与动态色彩强化)');
      } else {
        playerEl.classList.remove('vjs-enhanced');
        this.btnEnhance.classList.remove('active');
        this.showToast('画质增强已关闭 (原画渲染)');
      }

      this.updateBtnLabels();
      localStorage.setItem('vplayer_enhance_enabled', this.isEnhanced ? 'true' : 'false');
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
      this.toastEl.innerText = msg;
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
  window.ModernVideoPlayer = ModernVideoPlayer;

})(window);
