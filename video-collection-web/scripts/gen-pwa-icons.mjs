/**
 * PWA 图标生成脚本
 * 用无头浏览器将品牌 SVG 栅格化为各尺寸 PNG：
 *   - icon-192 / icon-512          普通图标（any purpose）
 *   - icon-maskable-192 / 512      自适应图标（60% 安全区）
 *   - apple-touch-icon (180)       iOS 主屏图标（不透明背景）
 * 用法：node scripts/gen-pwa-icons.mjs [chrome路径]
 * 说明：playwright-core 位于全局受管 workspace，此处按绝对路径引入（ESM 不读 NODE_PATH）。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const PW_CORE = 'file:///C:/Users/Administrator/.workbuddy-ai/binaries/node/workspace/node_modules/playwright-core/index.mjs';
const { chromium } = await import(PW_CORE);

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const svgPath = path.join(root, 'public/brand/bllii-symbol.svg');
const outDir = path.join(root, 'public/icons');
const browserPath = process.argv[2]
  || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

const svg = fs.readFileSync(svgPath, 'utf8');
const svgUri = 'data:image/svg+xml;base64,' + Buffer.from(svg).toString('base64');
fs.mkdirSync(outDir, { recursive: true });

// 背景与站点保持一致（bg-slate-50），避免透明图标在不同启动器下出现黑边
const BG = '#f8fafc';
const targets = [
  { file: 'icon-192.png', size: 192, scale: 0.76 },
  { file: 'icon-512.png', size: 512, scale: 0.76 },
  { file: 'icon-maskable-192.png', size: 192, scale: 0.60 },
  { file: 'icon-maskable-512.png', size: 512, scale: 0.60 },
  { file: 'apple-touch-icon.png', size: 180, scale: 0.74 },
];

const browser = await chromium.launch({
  executablePath: browserPath,
  args: ['--no-sandbox', '--disable-dev-shm-usage']
});
try {
  const page = await browser.newPage({ viewport: { width: 512, height: 512 }, deviceScaleFactor: 1 });
  for (const t of targets) {
    await page.setViewportSize({ width: t.size, height: t.size });
    const html = `<!doctype html><html><body style="margin:0;background:${BG}">`
      + `<div style="width:${t.size}px;height:${t.size}px;display:flex;align-items:center;justify-content:center;overflow:hidden">`
      + `<img src="${svgUri}" style="width:${Math.round(t.size * t.scale)}px;height:auto;display:block"></div></body></html>`;
    await page.goto('data:text/html;charset=utf-8,' + encodeURIComponent(html));
    await page.evaluate(() => new Promise((resolve) => {
      const img = document.querySelector('img');
      if (img.complete) resolve();
      else img.addEventListener('load', resolve, { once: true });
    }));
    await page.screenshot({ path: path.join(outDir, t.file), clip: { x: 0, y: 0, width: t.size, height: t.size } });
    console.log('generated', t.file, `${t.size}x${t.size}`);
  }
} finally {
  await browser.close();
}
console.log('PWA icons written to', outDir);
