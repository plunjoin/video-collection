import { readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const sprite = readFileSync(resolve(root, 'bllii-brand-kit/svg/bllii-ui.svg'), 'utf8');
const previewPath = resolve(root, 'bllii-brand-kit/ui-icons.html');
const preview = readFileSync(previewPath, 'utf8');
writeFileSync(previewPath, preview.replace(/<!-- brand-icons:start -->[\s\S]*?<!-- brand-icons:end -->/, () => `<!-- brand-icons:start -->${sprite}<!-- brand-icons:end -->`));
copyFileSync(resolve(root, 'bllii-brand-kit/svg/bllii-ui.svg'), resolve(root, 'video-collection-web/public/brand/bllii-ui.svg'));
const webPlayer = resolve(root, 'video-collection-web/public/players/videojs/modern-player.js');
let source = readFileSync(webPlayer, 'utf8');
source = source.replace(/const BRAND_ICON_SPRITE = .*?; \/\/ brand-sprite/, () => `const BRAND_ICON_SPRITE = ${JSON.stringify(sprite)}; // brand-sprite`);
writeFileSync(webPlayer, source);
writeFileSync(resolve(root, 'video-collection-api/players/videojs/modern-player.js'), source);
