import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PW_CORE = 'file:///C:/Users/Administrator/.workbuddy-ai/binaries/node/workspace/node_modules/playwright-core/index.mjs';
const { chromium } = await import(PW_CORE);

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(appRoot, '..');
const installerDir = path.resolve(appRoot, 'installer');

if (!fs.existsSync(installerDir)) {
  fs.mkdirSync(installerDir, { recursive: true });
}

function rgbaToBmp24(rgbaArray, width, height) {
  const rowSize = Math.floor((width * 3 + 3) / 4) * 4;
  const imageSize = rowSize * height;
  const fileSize = 54 + imageSize;
  const buf = Buffer.alloc(fileSize);

  buf.write('BM', 0);
  buf.writeUInt32LE(fileSize, 2);
  buf.writeUInt32LE(54, 10);
  buf.writeUInt32LE(40, 14);
  buf.writeInt32LE(width, 18);
  buf.writeInt32LE(height, 22);
  buf.writeUInt16LE(1, 26);
  buf.writeUInt16LE(24, 28);
  buf.writeUInt32LE(0, 30);
  buf.writeUInt32LE(imageSize, 34);

  let offset = 54;
  for (let y = height - 1; y >= 0; y--) {
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      buf[offset++] = rgbaArray[idx + 2]; // B
      buf[offset++] = rgbaArray[idx + 1]; // G
      buf[offset++] = rgbaArray[idx];     // R
    }
    const pad = rowSize - (width * 3);
    for (let p = 0; p < pad; p++) buf[offset++] = 0;
  }
  return buf;
}

const verticalSvgRaw = fs.readFileSync(path.resolve(repoRoot, 'bllii-brand-kit/svg/bllii-vertical.svg'), 'utf8');
const symbolSvgRaw = fs.readFileSync(path.resolve(repoRoot, 'bllii-brand-kit/svg/bllii-symbol.svg'), 'utf8');

// For dark background, make wordmark white
const verticalSvgWhiteWordmark = verticalSvgRaw.replace('fill="#353B58"', 'fill="#F9FAFF"');

const browser = await chromium.launch({
  executablePath: 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  headless: true
});

try {
  const page = await browser.newPage();

  // 1. Generate WizardImage (328x628)
  const wizardHtml = `
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        width: 328px;
        height: 628px;
        background: radial-gradient(circle at 50% 28%, rgba(255, 137, 199, 0.22) 0%, rgba(15, 23, 42, 0) 55%),
                    radial-gradient(circle at 20% 70%, rgba(75, 159, 255, 0.25) 0%, rgba(15, 23, 42, 0) 50%),
                    radial-gradient(circle at 80% 85%, rgba(154, 131, 255, 0.22) 0%, rgba(15, 23, 42, 0) 45%),
                    #0F172A;
        font-family: 'Segoe UI', 'SF Pro Display', -apple-system, BlinkMacSystemFont, sans-serif;
        color: #F9FAFF;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        align-items: center;
        padding: 56px 24px 44px;
        overflow: hidden;
        position: relative;
      }
      .glow-ring {
        position: absolute;
        width: 240px;
        height: 240px;
        border-radius: 50%;
        background: radial-gradient(circle, rgba(154, 131, 255, 0.35) 0%, rgba(75, 159, 255, 0) 70%);
        top: 80px;
        filter: blur(28px);
        pointer-events: none;
      }
      .logo-box {
        display: flex;
        flex-direction: column;
        align-items: center;
        z-index: 2;
        margin-top: 10px;
      }
      .logo-box svg {
        width: 200px;
        height: auto;
        filter: drop-shadow(0 12px 28px rgba(0, 0, 0, 0.45));
      }
      .footer-box {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
        z-index: 2;
        text-align: center;
      }
      .slogan {
        font-size: 15px;
        font-weight: 600;
        letter-spacing: 0.5px;
        background: linear-gradient(135deg, #FF89C7 0%, #AE8CFF 50%, #80B6FF 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
      }
      .subtext {
        font-size: 12px;
        color: #94A3B8;
        letter-spacing: 0.4px;
      }
    </style>
  </head>
  <body>
    <div class="glow-ring"></div>
    <div class="logo-box">
      ${verticalSvgWhiteWordmark}
    </div>
    <div class="footer-box">
      <div class="slogan">More Stories, Together</div>
      <div class="subtext">专属流媒体与视频合集</div>
    </div>
  </body>
  </html>
  `;

  await page.setViewportSize({ width: 328, height: 628 });
  await page.setContent(wizardHtml);

  // Capture canvas pixels
  const wizardPixels = await page.evaluate(async () => {
    const canvas = document.createElement('canvas');
    canvas.width = 328;
    canvas.height = 628;
    const ctx = canvas.getContext('2d');
    // Draw page via Image or directly to canvas
    // Or we can take screenshot
  });

  const wizardPngBuffer = await page.screenshot({ type: 'png' });
  
  // Use page to convert PNG to RGBA pixels
  const wizardRgba = await page.evaluate(async (pngBase64) => {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => {
        const canvas = document.createElement('canvas');
        canvas.width = 328;
        canvas.height = 628;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0);
        const data = ctx.getImageData(0, 0, 328, 628).data;
        resolve(Array.from(data));
      };
      img.src = 'data:image/png;base64,' + pngBase64;
    });
  }, wizardPngBuffer.toString('base64'));

  const wizardBmp = rgbaToBmp24(wizardRgba, 328, 628);
  fs.writeFileSync(path.resolve(installerDir, 'wizard.bmp'), wizardBmp);
  console.log('Saved wizard.bmp (328x628)');

  // 2. Generate WizardSmallImage (110x110)
  const smallHtml = `
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        width: 110px;
        height: 110px;
        background: transparent;
        display: flex;
        justify-content: center;
        align-items: center;
      }
      svg {
        width: 90px;
        height: 90px;
        filter: drop-shadow(0 4px 10px rgba(89, 123, 234, 0.4));
      }
    </style>
  </head>
  <body>
    ${symbolSvgRaw}
  </body>
  </html>
  `;

  await page.setViewportSize({ width: 110, height: 110 });
  await page.setContent(smallHtml);
  const smallPngBuffer = await page.screenshot({ type: 'png', omitBackground: false });

  const smallRgba = await page.evaluate(async (pngBase64) => {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => {
        const canvas = document.createElement('canvas');
        canvas.width = 110;
        canvas.height = 110;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#FFFFFF';
        ctx.fillRect(0, 0, 110, 110);
        ctx.drawImage(img, 0, 0);
        const data = ctx.getImageData(0, 0, 110, 110).data;
        resolve(Array.from(data));
      };
      img.src = 'data:image/png;base64,' + pngBase64;
    });
  }, smallPngBuffer.toString('base64'));

  const smallBmp = rgbaToBmp24(smallRgba, 110, 110);
  fs.writeFileSync(path.resolve(installerDir, 'wizard-small.bmp'), smallBmp);
  console.log('Saved wizard-small.bmp (110x110)');

} finally {
  await browser.close();
}
