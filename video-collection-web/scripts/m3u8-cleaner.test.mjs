import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const playerSource = readFileSync(new URL('../public/players/videojs/modern-player.js', import.meta.url), 'utf8');
const context = vm.createContext({ window: {}, URL, Blob, AbortController, AbortSignal, fetch, console });
vm.runInContext(playerSource, context);
const { cleanPlaylist, prepareClientPlaylist } = context.window.ModernVideoPlayer;
const origin = 'https://cdn.example/movie/index.m3u8';
const cases = JSON.parse(readFileSync(new URL('../../video-collection-app/test/fixtures/m3u8_cases.json', import.meta.url)));
const segments = text => text.split('\n').filter(line => line && !line.startsWith('#'));

for (const sample of cases) {
  test(sample.name, () => {
    const lines = ['#EXTM3U', '#EXT-X-MEDIA-SEQUENCE:0'];
    for (const [index, group] of [sample.before, sample.middle, sample.after].entries()) {
      if (index && !sample.noBoundary) lines.push('#EXT-X-DISCONTINUITY');
      for (const seq of group) lines.push(`#EXTINF:${index === 1 ? sample.middleDuration || 4 : 32},`, `movie${seq}.ts`);
    }
    lines.push('#EXT-X-ENDLIST');
    const cleaned = cleanPlaylist(lines.join('\n'), origin, sample);
    const want = [...sample.before, ...(sample.remove ? [] : sample.middle), ...sample.after].map(seq => `https://cdn.example/movie/movie${seq}.ts`);
    assert.deepEqual(segments(cleaned), want);
    assert.equal((cleaned.match(/#EXTINF:/g) || []).length, want.length);
    assert.match(cleaned, /#EXT-X-MEDIA-SEQUENCE:0/);
    assert.match(cleaned, /#EXT-X-ENDLIST$/);
  });
}

test('head, middle, tail and keyword ads retain movie segments', () => {
  const text = '#EXTM3U\n#EXTINF:4,\n9001.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n0.ts\n#EXTINF:4,\n1.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n10000.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n2.ts\n#EXTINF:4,\n/ad/promo.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n10001.ts\n#EXT-X-ENDLIST';
  const cleaned = cleanPlaylist(text, origin);
  assert.deepEqual(segments(cleaned), ['0.ts', '1.ts', '2.ts'].map(uri => new URL(uri, origin).href));
});

test('preserves encryption state and original implicit IV after deleting a segment', () => {
  const text = '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:10\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:4,\n/ad/0.ts\n#EXTINF:4,\n1.ts\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:4,\n2.ts\n#EXT-X-ENDLIST';
  const cleaned = cleanPlaylist(text, origin);
  assert.match(cleaned, /URI="https:\/\/cdn.example\/movie\/key.bin",IV=0x0000000000000000000000000000000b/);
  assert.match(cleaned, /#EXT-X-KEY:METHOD=NONE/);
  assert.equal(segments(cleaned).length, 2);
});

test('preserves initialization map, byte offsets and real discontinuities', () => {
  const text = '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4,\n#EXT-X-BYTERANGE:100@0\nmovie.mp4\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\n#EXT-X-BYTERANGE:100\nmovie.mp4\n#EXT-X-ENDLIST';
  const cleaned = cleanPlaylist(text, origin);
  assert.match(cleaned, /URI="https:\/\/cdn.example\/movie\/init.mp4"/);
  assert.match(cleaned, /#EXT-X-BYTERANGE:100@100/);
  assert.match(cleaned, /#EXT-X-DISCONTINUITY/);
});

test('keeps live lists and prevents empty output', () => {
  const live = '#EXTM3U\n#EXTINF:4,\n/ad/live.ts';
  assert.equal(segments(cleanPlaylist(live, origin)).length, 1);
  assert.equal(segments(cleanPlaylist(`${live}\n#EXT-X-ENDLIST`, origin)).length, 1);
  assert.throws(() => cleanPlaylist('<html>error</html>', origin));
});

test('fetches master, variants and audio directly and releases all local resources', async () => {
  const fetched = [], local = new Map(), revoked = [];
  const remote = new Map([
    [origin, '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="audio/index.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=800000,AUDIO="audio"\nvideo/index.m3u8'],
    ['https://cdn.example/movie/audio/index.m3u8', '#EXTM3U\n#EXTINF:4,\nsound.aac\n#EXT-X-ENDLIST'],
    ['https://cdn.example/movie/video/index.m3u8', '#EXTM3U\n#EXTINF:4,\n/ad/promo.ts\n#EXTINF:4,\n1.ts\n#EXT-X-ENDLIST'],
  ]);
  const resource = await prepareClientPlaylist(origin, {
    fetchPlaylist: async url => { fetched.push(url); return { ok: true, url, text: async () => remote.get(url) }; },
    createURL: text => { const url = `blob:test/${local.size}`; local.set(url, text); return url; },
    revokeURL: url => revoked.push(url),
  });
  assert.equal(fetched.length, 3);
  assert(fetched.every(url => url.startsWith('https://cdn.example/')));
  assert.match(local.get(resource.url), /URI="blob:test\/0"/);
  assert.equal(segments(local.get('blob:test/1')).length, 1);
  resource.dispose(); resource.dispose();
  assert.equal(revoked.length, 3);
});

test('live child, cycles, fetch failures and aborts release resources', async () => {
  for (const failure of ['live', 'cycle', 'network', 'abort']) {
    const created = [], revoked = [];
    const controller = new AbortController();
    const remote = new Map([
      [origin, '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\ngood.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2\nbad.m3u8'],
      ['https://cdn.example/movie/good.m3u8', '#EXTM3U\n#EXTINF:4,\n0.ts\n#EXT-X-ENDLIST'],
      ['https://cdn.example/movie/bad.m3u8', failure === 'cycle' ? '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nindex.m3u8' : '#EXTM3U\n#EXTINF:4,\n0.ts'],
    ]);
    await assert.rejects(prepareClientPlaylist(origin, {
      signal: controller.signal,
      fetchPlaylist: async url => {
        if (url.endsWith('bad.m3u8')) {
          if (failure === 'network') throw new Error('network');
          if (failure === 'abort') controller.abort();
        }
        return { ok: true, url, text: async () => remote.get(url) };
      },
      createURL: () => { const url = `blob:${created.length}`; created.push(url); return url; },
      revokeURL: url => revoked.push(url),
    }));
    assert.deepEqual(revoked, created);
  }
});

test('a slow previous episode cannot overwrite a newer selection', async () => {
  let finish;
  // 使用真实 playEpisode 控制流程，暂停在第一集的异步列表加载处。
  const firstFetch = new Promise(resolve => { finish = resolve; });
  context.fetch = async () => { await firstFetch; return { ok: true, url: origin, text: async () => '#EXTM3U\n#EXTINF:4,\n0.ts\n#EXT-X-ENDLIST' }; };
  const player = Object.create(context.window.ModernVideoPlayer.prototype);
  let selected;
  Object.assign(player, {
    routes: [{ player_code: 'm3u8', episodes: [{ name: 'slow', url: origin }, { name: 'new', url: 'https://cdn.example/new.mp4' }] }],
    options: { cleanM3U8: true }, sourceGeneration: 0,
    player: { pause() {}, src(source) { selected = source.src; }, play() { return Promise.resolve(); } },
    clearCountdown() {}, closeEpisodesDrawer() {}, resetPreview() {}, updateRoutesUI() {}, updateEpisodesDrawerUI() {}, showToast() {},
  });
  const previous = player.playEpisode(0, 0);
  await player.playEpisode(0, 1);
  finish(); await previous;
  assert.equal(selected, 'https://cdn.example/new.mp4');
});

test('API-served and Web-served player implementations stay identical', () => {
  assert.equal(playerSource, readFileSync(new URL('../../video-collection-api/players/videojs/modern-player.js', import.meta.url), 'utf8'));
});
