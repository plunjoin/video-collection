import React from 'react';
import { renderToString } from 'react-dom/server.browser';
import App from './App';

export function render(url: string, props: Record<string, any>) {
  const html = renderToString(
    <div id="root">
      <App url={url} {...props} />
    </div>
  );
  const head = `<title>${props?.title || 'bllii — 在更多的故事里，遇见更好的你'}</title>` +
    `<meta name="description" content="${props?.description || 'bllii 动漫番剧在线播放与聚合平台'}">` +
    `<link rel="icon" type="image/svg+xml" href="/brand/bllii-symbol.svg">` +
    `<link rel="manifest" href="/manifest.webmanifest">` +
    `<meta name="theme-color" content="#597bea">` +
    `<script src="/js/tracker.js" defer></script>`;
  return { html, head };
}
