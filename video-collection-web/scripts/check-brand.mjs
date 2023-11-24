import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { tmpdir } from 'node:os';

const require = createRequire(import.meta.url);
const { chromium } = require(process.argv[2] || 'playwright');
const base = process.argv[3] || 'http://localhost:4322';
const output = resolve(tmpdir(), 'bllii-brand-check');
mkdirSync(output, { recursive: true });
const browser = await chromium.launch({ headless: true });
const errors = [];
try {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(base, { waitUntil: 'networkidle', timeout: 90000 });
  await page.addStyleTag({ content: 'astro-dev-toolbar { display: none !important; }' });
  await page.locator('[data-mood="0"]').waitFor();
  const videoId = Number((await page.locator('.video-card__link').first().getAttribute('href')).split('/').at(-1));
  assert(videoId > 0, 'Homepage must show real videos');
  const videoName = await page.locator('.video-card h3').first().textContent();
  const saveStory = page.locator('[data-pocket-id]').first();
  await saveStory.click();
  assert.equal(await saveStory.getAttribute('aria-pressed'), 'true');
  await page.locator('[data-open-pocket]').click();
  assert.equal(await page.locator('.pocket-row').count(), 1);
  await page.screenshot({ path: resolve(output, 'pocket-desktop.png'), animations: 'disabled' });
  await page.locator('[data-pocket-close]').click();
  await page.locator('[data-dot="1"]').click();
  assert.equal(await page.locator('[data-dot="1"]').getAttribute('aria-pressed'), 'true');
  for (let i = 0; i < 4; i++) {
    await page.locator(`[data-mood="${i}"]`).click();
    assert.equal(await page.locator(`[data-mood="${i}"]`).getAttribute('aria-pressed'), 'true');
    const selectedName = await page.locator('[data-mood-title]').textContent();
    if (i === 3) {
      await page.locator('[data-shuffle]').click();
      assert.notEqual(await page.locator('[data-mood-title]').textContent(), selectedName, 'Shuffle should choose a different video');
    }
  }
  await page.evaluate(({ videoId, videoName }) => {
    localStorage.setItem('bllii_story_bookmark', JSON.stringify({ videoId, videoName, episodeName: '第01话', episodeIndex: 0, routeIndex: 0, currentTime: 92, duration: 1440, updatedAt: Date.now() }));
  }, { videoId, videoName });
  await page.reload({ waitUntil: 'networkidle' });
  await page.addStyleTag({ content: 'astro-dev-toolbar { display: none !important; }' });
  assert.equal(await page.locator('[data-story-bookmark]').isVisible(), true);
  assert.equal(await page.locator('[data-pocket-id]').first().getAttribute('aria-pressed'), 'true');
  assert.match(await page.locator('[data-resume-meta]').textContent(), /1:32/);
  await page.screenshot({ path: resolve(output, 'home-desktop.png'), fullPage: true });
  const checkOverflow = async () => assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Page must fit the viewport');
  await checkOverflow();
  await page.setViewportSize({ width: 375, height: 812 });
  await page.screenshot({ path: resolve(output, 'home-mobile.png'), fullPage: true });
  await checkOverflow();
  await page.locator('[data-resume-dismiss]').click();
  assert.equal(await page.locator('[data-story-bookmark]').isVisible(), false);
  await page.evaluate(() => localStorage.setItem('bllii_story_bookmark', '{bad json'));
  await page.reload({ waitUntil: 'networkidle' });
  assert.equal(await page.locator('[data-story-bookmark]').isVisible(), false);

  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.route('**/api/m3u8/clean?**', route => route.abort());
  await page.goto(`${base}/play/${videoId}`, { waitUntil: 'networkidle', timeout: 90000 });
  await page.addStyleTag({ content: 'astro-dev-toolbar { display: none !important; }' });
  await page.locator('.vjs-btn-settings').waitFor({ timeout: 30000 });
  assert.equal(await page.locator('.vjs-btn-enhance').count(), 0);
  const checkNativeIcons = async () => {
    const states = await page.locator('.vjs-play-control,.vjs-mute-control,.vjs-fullscreen-control').evaluateAll(elements => elements.map(el => ({
      icons: el.querySelectorAll('.bllii-player-icon').length,
      fontIcon: getComputedStyle(el.querySelector('.vjs-icon-placeholder'), '::before').display,
    })));
    states.forEach(state => { assert.equal(state.icons, 1, 'Exactly one SVG per control'); assert.equal(state.fontIcon, 'none', 'Native font icons must be hidden'); });
  };
  await checkNativeIcons();
  await page.locator('.player-stage').click({ button: 'right', position: { x: 100, y: 70 } });
  assert.equal(await page.locator('.bllii-settings-panel').evaluate(el => el.open), true);
  await page.locator('[data-picture-preset]').selectOption('soft');
  assert.match(await page.locator('#vplayer-element').getAttribute('style'), /contrast\(0.92\)/);
  await page.locator('[data-settings-tab="sound"]').click();
  assert.equal(await page.locator('[data-sound-mode]').isDisabled(), true, 'Unavailable remote media must keep original audio');
  await page.screenshot({ path: resolve(output, 'settings-desktop.png'), animations: 'disabled' });
  await page.locator('[data-settings-reset]').click();
  await page.locator('.bllii-panel-close').click();
  assert.match(await page.locator('#vplayer-element').getAttribute('style'), /--bllii-picture-filter: none/);
  await page.locator('.vjs-btn-autoplay').click();
  assert.equal(await page.locator('[data-autoplay-status]').textContent(), '自动连播已关闭');
  await page.locator('.vjs-btn-ratio').click();
  assert.match(await page.locator('.vjs-btn-ratio').getAttribute('aria-label'), /16:9/);
  await page.locator('.vjs-btn-episodes').click();
  assert.equal(await page.locator('.vjs-episodes-drawer').evaluate(el => el.classList.contains('open')), true);
  await page.locator('.vjs-drawer-close').click();
  await page.locator('[data-focus-player]').click();
  assert.equal(await page.locator('.player-room__sidebar').isVisible(), false);
  await page.locator('[data-focus-player]').click();
  assert.equal(await page.locator('.player-room__sidebar').isVisible(), true);

  // A generated video isolates player and bookmark checks from third party stream availability.
  await page.evaluate(async () => {
    const canvas = document.createElement('canvas'); canvas.width = 480; canvas.height = 270;
    const ctx = canvas.getContext('2d');
    let frame = 0;
    const timer = setInterval(() => {
      ctx.fillStyle = '#edf5ff'; ctx.fillRect(0, 0, 480, 270);
      ctx.fillStyle = '#4b9fff'; ctx.fillRect((frame++ * 4) % 400, 100, 80, 70);
      ctx.fillStyle = '#353b58'; ctx.font = '24px sans-serif'; ctx.fillText('bllii / player check', 100, 60);
    }, 50);
    const stream = canvas.captureStream(20);
    const recorder = new MediaRecorder(stream, { mimeType: 'video/webm' });
    const chunks = [];
    const finished = new Promise(resolve => {
      recorder.ondataavailable = event => chunks.push(event.data);
      recorder.onstop = () => resolve(new Blob(chunks, { type: 'video/webm' }));
    });
    recorder.start();
    await new Promise(resolve => setTimeout(resolve, 5000));
    recorder.stop(); clearInterval(timer); stream.getTracks().forEach(track => track.stop());
    const blob = await finished;
    const player = videojs.getPlayer('vplayer-element');
    player.src({ src: URL.createObjectURL(blob), type: 'video/webm' });
    await player.play();
  });
  await page.waitForFunction(() => videojs.getPlayer('vplayer-element').currentTime() > 3.2, { timeout: 15000 });
  await page.evaluate(() => videojs.getPlayer('vplayer-element').pause());
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('bllii_story_bookmark') || 'null'));
  assert(saved?.currentTime > 3, 'Playback must update the story bookmark');
  await page.locator('.vjs-playback-rate > button').click();
  await page.locator('.vjs-playback-rate .vjs-menu-item').filter({ hasText: /^1.5x$/ }).click();
  await page.waitForFunction(() => videojs.getPlayer('vplayer-element').playbackRate() === 1.5);
  assert.equal(await page.evaluate(() => videojs.getPlayer('vplayer-element').playbackRate()), 1.5);
  await page.locator('.vjs-playback-rate > button').click();
  await page.screenshot({ path: resolve(output, 'rate-desktop.png'), animations: 'disabled' });
  assert(await page.locator('.vjs-playback-rate .vjs-menu-content').evaluate(el => el.scrollHeight <= el.clientHeight + 1), 'Every rate option must fit the menu');
  await page.locator('.vjs-playback-rate .vjs-menu-item').filter({ hasText: /^1x$/ }).click();
  await page.waitForFunction(() => videojs.getPlayer('vplayer-element').playbackRate() === 1);
  await checkNativeIcons();
  await page.locator('.vjs-mute-control').click();
  await page.waitForFunction(() => document.querySelector('.vjs-mute-control use').getAttribute('href') === '#bllii-muted');
  assert.equal(await page.locator('.vjs-mute-control use').getAttribute('href'), '#bllii-muted');
  await page.locator('.vjs-mute-control').click();
  await page.locator('.vjs-btn-settings').click();
  await page.locator('[data-settings-tab="sound"]').click();
  await page.keyboard.press('ArrowLeft');
  assert.equal(await page.locator('[data-settings-tab="picture"]').getAttribute('aria-selected'), 'true');
  await page.locator('[data-settings-tab="sound"]').click();
  assert.equal(await page.locator('[data-sound-mode]').isDisabled(), false);
  await page.locator('[data-sound-mode]').selectOption('dialogue');
  await page.waitForFunction(() => document.querySelector('[data-sound-state]').textContent === '对白清晰');
  await page.locator('[data-settings-reset]').click();
  await page.locator('.bllii-panel-close').click();
  const initialTime = await page.evaluate(() => videojs.getPlayer('vplayer-element').currentTime());
  await page.locator('#vplayer-element > .vjs-control-bar .vjs-progress-control').scrollIntoViewIfNeeded();
  const track = await page.locator('#vplayer-element > .vjs-control-bar .vjs-progress-holder').boundingBox();
  await page.mouse.move(track.x + track.width * .25, track.y + 2);
  await page.locator('.bllii-frame-preview.is-ready').waitFor({ timeout: 15000 }).catch(async error => {
    console.log('Preview state', await page.evaluate(({x,y}) => ({ duration: videojs.getPlayer('vplayer-element').duration(), target: document.elementFromPoint(x,y)?.outerHTML.slice(0,400), settingsOpen: document.querySelector('.bllii-settings-panel').open, popup: document.querySelector('.bllii-frame-preview').outerHTML }), {x:track.x + track.width * .25,y:track.y+2}));
    await page.screenshot({path:resolve(output,'preview-failure.png')});
    throw error;
  });
  assert(await page.locator('.bllii-frame-preview video').evaluate(video => video.readyState >= 2));
  assert.equal(await page.evaluate(() => videojs.getPlayer('vplayer-element').currentTime()), initialTime, 'Preview must not seek the main video');
  await page.screenshot({ path: resolve(output, 'preview-desktop.png'), animations: 'disabled' });
  await page.mouse.move(track.x + track.width * .25 + 1, track.y + 2);
  await page.waitForTimeout(6500);
  assert(await page.locator('.bllii-frame-preview.is-ready').isVisible(), 'A ready frame must not time out');
  await page.mouse.move(10, 10);
  await page.locator('#vplayer-element > .vjs-control-bar .vjs-fullscreen-control').click();
  await page.waitForFunction(() => !!document.fullscreenElement);
  assert.equal(await page.locator('.vjs-episodes-drawer').isVisible(), false, 'Closed drawer must be hidden in fullscreen');
  await page.locator('.vjs-btn-settings').click();
  assert(await page.locator('.bllii-settings-panel').isVisible(), 'Settings must work in fullscreen');
  await page.screenshot({ path: resolve(output, 'settings-fullscreen.png'), animations: 'disabled' });
  await page.keyboard.press('Escape');
  await page.evaluate(() => document.exitFullscreen());
  await page.screenshot({ path: resolve(output, 'player-desktop.png'), fullPage: true });
  await checkOverflow();
  for (const width of [375, 320]) {
    await page.setViewportSize({ width, height: 812 });
    await checkOverflow();
    assert(await page.locator('.vjs-btn-episodes').isVisible());
    const controlsFit = await page.locator('#vplayer-element > .vjs-control-bar').evaluate(el => {
      const bounds = el.getBoundingClientRect();
      return [...el.children].filter(child => getComputedStyle(child).display !== 'none').every(child => child.getBoundingClientRect().right <= bounds.right + 1);
    });
    assert(controlsFit, `Player controls must fit ${width}px`);
    await page.locator('.vjs-btn-settings').click();
    assert(await page.locator('.bllii-settings-panel').evaluate(el => { const r = el.getBoundingClientRect(); return r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight; }), 'Settings must fit the viewport');
    await page.screenshot({ path: resolve(output, `settings-${width}.png`), animations: 'disabled' });
    await page.locator('.bllii-panel-close').click();
    await page.screenshot({ path: resolve(output, `player-${width}.png`), fullPage: true });
  }
  await page.evaluate(() => {
    const player = videojs.getPlayer('vplayer-element');
    player.src(player.currentSource());
  });
  await page.waitForFunction(() => !document.querySelector('.bllii-frame-preview video'));
  assert.deepEqual(errors, [], 'No browser script errors');
  console.log(`Passed: carousel, moods, pocket persistence, bookmarks, single control icons, rate menu, filters, safe audio effects, frame preview, focus mode and mobile layouts. Screenshots: ${output}`);
} finally {
  await browser.close();
}
