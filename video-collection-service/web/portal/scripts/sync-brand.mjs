import { readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';

// 仓库根：web/portal/scripts -> portal -> web -> video-collection-service -> 仓库根
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');
const sprite = readFileSync(resolve(root, 'bllii-brand-kit/svg/bllii-ui.svg'), 'utf8');
const previewPath = resolve(root, 'bllii-brand-kit/ui-icons.html');
const preview = readFileSync(previewPath, 'utf8');
writeFileSync(previewPath, preview.replace(/<!-- brand-icons:start -->[\s\S]*?<!-- brand-icons:end -->/, () => `<!-- brand-icons:start -->${sprite}<!-- brand-icons:end -->`));
copyFileSync(resolve(root, 'bllii-brand-kit/svg/bllii-ui.svg'), resolve(root, 'video-collection-service/web/portal/public/brand/bllii-ui.svg'));
const webPlayer = resolve(root, 'video-collection-service/web/portal/public/players/videojs/modern-player.js');
let source = readFileSync(webPlayer, 'utf8');
source = source.replace(/const BRAND_ICON_SPRITE = .*?; \/\/ brand-sprite/, () => `const BRAND_ICON_SPRITE = ${JSON.stringify(sprite)}; // brand-sprite`);
writeFileSync(webPlayer, source);
writeFileSync(resolve(root, 'video-collection-service/players/videojs/modern-player.js'), source);
