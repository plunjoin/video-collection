import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PW_CORE = 'file:///C:/Users/Administrator/.workbuddy-ai/binaries/node/workspace/node_modules/playwright-core/index.mjs';
const { chromium } = await import(PW_CORE);

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(appRoot, '..');

const sourcePath = process.argv[2] 
  ? path.resolve(process.argv[2])
  : path.resolve(repoRoot, 'bllii-brand-kit/png/bllii-app-light.png');

const browserPath = process.env.EDGE_PATH 
  || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

if (!fs.existsSync(sourcePath)) {
  console.error('Source icon not found:', sourcePath);
  process.exit(1);
}

console.log('Source icon:', sourcePath);
console.log('App root:', appRoot);

// Prepare ICO generator
function createIco(pngBuffersWithSize) {
  const count = pngBuffersWithSize.length;
  const headerSize = 6;
  const dirEntrySize = 16;
  const dirSize = count * dirEntrySize;
  let offset = headerSize + dirSize;

  const header = Buffer.alloc(headerSize);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // 1 = ICO
  header.writeUInt16LE(count, 4); // count

  const dirEntries = [];
  const imageBuffers = [];

  for (const item of pngBuffersWithSize) {
    const entry = Buffer.alloc(dirEntrySize);
    entry.writeUInt8(item.width >= 256 ? 0 : item.width, 0);
    entry.writeUInt8(item.height >= 256 ? 0 : item.height, 1);
    entry.writeUInt8(0, 2); // color count
    entry.writeUInt8(0, 3); // reserved
    entry.writeUInt16LE(1, 4); // color planes
    entry.writeUInt16LE(32, 6); // bits per pixel
    entry.writeUInt32LE(item.buffer.length, 8); // size of image
    entry.writeUInt32LE(offset, 12); // offset

    dirEntries.push(entry);
    imageBuffers.push(item.buffer);
    offset += item.buffer.length;
  }

  return Buffer.concat([header, ...dirEntries, ...imageBuffers]);
}

const sourceBuffer = fs.readFileSync(sourcePath);
const srcDataUrl = 'data:image/png;base64,' + sourceBuffer.toString('base64');

const browser = await chromium.launch({
  executablePath: browserPath,
  args: ['--no-sandbox', '--disable-dev-shm-usage']
});

try {
  const page = await browser.newPage();
  await page.setContent(`<!doctype html><html><body><img id="src" src="${srcDataUrl}"></body></html>`);
  await page.waitForFunction(() => {
    const el = document.getElementById('src');
    return el && el.complete && el.naturalWidth > 0;
  });

  async function renderPng(width, height) {
    const dataUrl = await page.evaluate(({ w, h }) => {
      const src = document.getElementById('src');
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(src, 0, 0, w, h);
      return canvas.toDataURL('image/png');
    }, { w: width, h: height });
    return Buffer.from(dataUrl.split(',')[1], 'base64');
  }

  // Define all destination targets
  const androidTargets = [
    { file: 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png', size: 48 },
    { file: 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png', size: 72 },
    { file: 'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', size: 96 },
    { file: 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', size: 144 },
    { file: 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', size: 192 },
  ];

  const iosTargets = [
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png', size: 20 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png', size: 40 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png', size: 60 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png', size: 29 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png', size: 58 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png', size: 87 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png', size: 40 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png', size: 80 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png', size: 120 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png', size: 120 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png', size: 180 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png', size: 76 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png', size: 152 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png', size: 167 },
    { file: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png', size: 1024 },
  ];

  const macosTargets = [
    { file: 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png', size: 16 },
    { file: 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png', size: 32 },
    { file: 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png', size: 64 },
    { file: 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png', size: 128 },
    { file: 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png', size: 256 },
    { file: 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png', size: 512 },
    { file: 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png', size: 1024 },
  ];

  const webTargets = [
    { file: 'web/icons/Icon-192.png', size: 192 },
    { file: 'web/icons/Icon-512.png', size: 512 },
    { file: 'web/icons/Icon-maskable-192.png', size: 192 },
    { file: 'web/icons/Icon-maskable-512.png', size: 512 },
    { file: 'web/favicon.png', size: 32 },
  ];

  const cache = new Map();
  async function getCachedPng(size) {
    if (!cache.has(size)) {
      if (size === 1024 && sourceBuffer.length > 0) {
        // If 1024, can use directly
        cache.set(size, sourceBuffer);
      } else {
        const buf = await renderPng(size, size);
        cache.set(size, buf);
      }
    }
    return cache.get(size);
  }

  // 1. Android
  console.log('\n[Android]');
  for (const t of androidTargets) {
    const dest = path.resolve(appRoot, t.file);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const buf = await getCachedPng(t.size);
    fs.writeFileSync(dest, buf);
    console.log(`  ✓ ${t.file} (${t.size}x${t.size})`);
  }

  // 2. iOS
  console.log('\n[iOS]');
  for (const t of iosTargets) {
    const dest = path.resolve(appRoot, t.file);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const buf = await getCachedPng(t.size);
    fs.writeFileSync(dest, buf);
    console.log(`  ✓ ${t.file} (${t.size}x${t.size})`);
  }

  // 3. macOS
  console.log('\n[macOS]');
  for (const t of macosTargets) {
    const dest = path.resolve(appRoot, t.file);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const buf = await getCachedPng(t.size);
    fs.writeFileSync(dest, buf);
    console.log(`  ✓ ${t.file} (${t.size}x${t.size})`);
  }

  // 4. Windows ICO
  console.log('\n[Windows]');
  const icoSizes = [16, 32, 48, 64, 128, 256];
  const icoEntries = [];
  for (const sz of icoSizes) {
    const buf = await getCachedPng(sz);
    icoEntries.push({ width: sz, height: sz, buffer: buf });
  }
  const icoBuf = createIco(icoEntries);
  const icoDest = path.resolve(appRoot, 'windows/runner/resources/app_icon.ico');
  fs.mkdirSync(path.dirname(icoDest), { recursive: true });
  fs.writeFileSync(icoDest, icoBuf);
  console.log(`  ✓ windows/runner/resources/app_icon.ico (${icoSizes.join(', ')} px)`);

  // 5. Web
  console.log('\n[Web]');
  for (const t of webTargets) {
    const dest = path.resolve(appRoot, t.file);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const buf = await getCachedPng(t.size);
    fs.writeFileSync(dest, buf);
    console.log(`  ✓ ${t.file} (${t.size}x${t.size})`);
  }

  // 6. Assets brand
  console.log('\n[Assets]');
  const brandDest = path.resolve(appRoot, 'assets/brand/bllii-app-light.png');
  fs.mkdirSync(path.dirname(brandDest), { recursive: true });
  fs.copyFileSync(sourcePath, brandDest);
  console.log(`  ✓ assets/brand/bllii-app-light.png`);

  console.log('\nAll app icons successfully replaced with /bllii-brand-kit/png/bllii-app-light.png!');
} finally {
  await browser.close();
}
