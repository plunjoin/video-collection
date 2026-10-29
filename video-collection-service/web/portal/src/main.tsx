import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
// 仅 dev 使用（webfront DevServer 固定加载 /src/main.tsx 并调用导出的 render()）。
// 生产构建入口仍是 entry-client.tsx，此文件不参与 wf build。
// 样式直引各文件而非 bundle.css：dev 的按需转译不展开 @import，
// 注入 <style> 后相对 @import 会按文档 URL 解析导致 404。
import './styles/tailwind.css';
import './styles/brand.css';
import './styles/pages.css';
import './styles/dialogs.css';
import './styles/members.css';
import './styles/delight.css';
import './styles/ads.css';
import './styles/festival.css';
import './styles/growth.css';
import './styles/discussion.css';
import './styles/inbox.css';
import './styles/community.css';
import './styles/news-detail.css';

type RootHandle = ReturnType<typeof createRoot>;

declare global {
  interface Window {
    __wfDevRoot?: RootHandle;
  }
}

// dev shell 无 __WF_DATA__ 注水，各页面在 props 为空时自行走 /api 客户端取数。
export function render() {
  const el = document.getElementById('root');
  if (!el) return;
  // HMR 会重新执行本模块，用 window 缓存 root 避免对同一容器重复 createRoot
  if (!window.__wfDevRoot) {
    window.__wfDevRoot = createRoot(el);
  }
  window.__wfDevRoot.render(<App url={window.location.pathname + window.location.search} />);
}
