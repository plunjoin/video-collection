"""Sync bllii source assets into the web and Flutter clients (requires Pillow)."""
from pathlib import Path
import json
import shutil
from PIL import Image

root = Path(__file__).resolve().parents[1]
kit = root / 'bllii-brand-kit'
web = root / 'video-collection-web'
app = root / 'video-collection-app'
web_brand = web / 'public/brand'
app_brand = app / 'assets/brand'
web_brand.mkdir(parents=True, exist_ok=True)
app_brand.mkdir(parents=True, exist_ok=True)
for source in (kit / 'svg').glob('*.svg'):
    shutil.copy2(source, web_brand / source.name)
shutil.copy2(kit / 'animation/bllii-loading.svg', web_brand / 'bllii-loading.svg')
for name in ['bllii-horizontal', 'bllii-horizontal-white', 'bllii-symbol', 'bllii-app-light-fullbleed']:
    source = Image.open(kit / f'png/{name}.png')
    source.thumbnail((720, 720), Image.Resampling.LANCZOS)
    source.save(app_brand / f'{name}.png', optimize=True)
shutil.copy2(kit / 'animation/bllii-loading.gif', app_brand / 'bllii-loading.gif')

# Native intro follows animation/bllii-intro.svg timing. Split its original
# wordmark into transparent letters so Flutter can stagger them independently.
wordmark = Image.open(kit / 'png/bllii-wordmark.png').convert('RGBA')
scale_x, scale_y = wordmark.width / 449, wordmark.height / 257
for index, (left, right) in enumerate([(0, 160), (173, 223), (236, 286), (302, 352), (367, 417)]):
    letter = wordmark.crop((round((left + 16) * scale_x), round(16 * scale_y),
                            round((right + 16) * scale_x), round(241 * scale_y)))
    letter.thumbnail((320, 450), Image.Resampling.LANCZOS)
    letter.save(app_brand / f'bllii-intro-letter-{index}.png', optimize=True)


icon = Image.open(kit / 'png/bllii-app-light-fullbleed.png').convert('RGB')
def save_icon(path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    icon.resize((size, size), Image.Resampling.LANCZOS).save(path)

for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save_icon(app / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
for relative in ['ios/Runner/Assets.xcassets/AppIcon.appiconset', 'macos/Runner/Assets.xcassets/AppIcon.appiconset']:
    folder = app / relative
    data = json.loads((folder / 'Contents.json').read_text())
    for entry in data['images']:
        if entry.get('filename'):
            size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
            save_icon(folder / entry['filename'], size)
for size in (192, 512):
    save_icon(app / f'web/icons/Icon-{size}.png', size)
    save_icon(app / f'web/icons/Icon-maskable-{size}.png', size)
save_icon(app / 'web/favicon.png', 32)
icon.save(app / 'windows/runner/resources/app_icon.ico', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print('Synced bllii logos, loading animation and platform icons.')
