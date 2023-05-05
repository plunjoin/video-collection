import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { gzipSync } from 'node:zlib';
import test from 'node:test';
import { getInternalApiUrl, proxyApiRequest } from '../src/lib/api-server.ts';

test('Node API proxy', async (t) => {
  const previousInternal = process.env.INTERNAL_API_URL;
  const previousPublic = process.env.PUBLIC_API_URL;
  const backend = createServer(async (req, res) => {
    if (req.url === '/api/segment') {
      res.writeHead(206, { 'Content-Type': 'video/mp2t', 'Content-Range': 'bytes 0-3/10' });
      res.end(Buffer.from([0x47, 0x00, 0xff, 0x10]));
    } else if (req.url === '/api/cookies') {
      res.writeHead(200, {
        'Content-Type': 'application/json', 'Content-Encoding': 'gzip',
        'Set-Cookie': ['session=one; Path=/; HttpOnly', 'pref=two; Path=/'],
      });
      res.end(gzipSync('{"code":1}'));
    } else {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      res.writeHead(req.url === '/api/denied' ? 401 : 200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        url: req.url, method: req.method, authorization: req.headers.authorization,
        cookie: req.headers.cookie, body: Buffer.concat(chunks).toString(),
      }));
    }
  });
  backend.listen(0, '127.0.0.1');
  await once(backend, 'listening');
  const backendUrl = `http://127.0.0.1:${backend.address().port}`;
  process.env.INTERNAL_API_URL = backendUrl;

  t.after(async () => {
    for (const [name, value] of [['INTERNAL_API_URL', previousInternal], ['PUBLIC_API_URL', previousPublic]]) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
    await new Promise(resolve => backend.close(resolve));
  });
  const request = (path, options) => new Request(`http://localhost:4321${path}`, options);

  await t.test('forwards API path and encoded query to the configured backend', async () => {
    process.env.PUBLIC_API_URL = 'https://wrong.example';
    assert.equal(getInternalApiUrl(), backendUrl);
    const path = '/api/videos?keyword=%E5%8A%A8%E6%BC%AB&page=2';
    const response = await proxyApiRequest(request(path));
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type'), /application\/json/);
    assert.equal((await response.json()).url, path);
  });

  await t.test('forwards POST bodies, bearer tokens and cookies', async () => {
    const body = JSON.stringify({ video_id: 123, episode_index: 2 });
    const response = await proxyApiRequest(request('/api/user/history', {
      method: 'POST', body,
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer test-token', Cookie: 'auth_token=test-token' },
    }));
    assert.deepEqual(await response.json(), {
      url: '/api/user/history', method: 'POST', authorization: 'Bearer test-token',
      cookie: 'auth_token=test-token', body,
    });
  });

  await t.test('preserves binary partial responses', async () => {
    const segment = await proxyApiRequest(request('/api/segment', { headers: { Range: 'bytes=0-3' } }));
    assert.equal(segment.status, 206);
    assert.equal(segment.headers.get('content-range'), 'bytes 0-3/10');
    assert.deepEqual(Buffer.from(await segment.arrayBuffer()), Buffer.from([0x47, 0x00, 0xff, 0x10]));
  });

  await t.test('preserves cookies and removes compression headers after fetch decodes the body', async () => {
    const response = await proxyApiRequest(request('/api/cookies'));
    assert.equal(response.headers.get('content-encoding'), null);
    assert.equal(response.headers.get('content-length'), null);
    assert.deepEqual(response.headers.getSetCookie(), ['session=one; Path=/; HttpOnly', 'pref=two; Path=/']);
    assert.deepEqual(await response.json(), { code: 1 });
  });

  await t.test('preserves backend authentication errors', async () => {
    const response = await proxyApiRequest(request('/api/denied'));
    assert.equal(response.status, 401);
    assert.equal((await response.json()).url, '/api/denied');
  });

  await t.test('returns JSON when the backend cannot be reached', async () => {
    // 无效端口保证请求失败，不依赖机器上是否有其他服务。
    process.env.INTERNAL_API_URL = 'http://127.0.0.1:0';
    const response = await proxyApiRequest(request('/api/videos'));
    assert.equal(response.status, 502);
    assert.equal((await response.json()).code, 0);
    process.env.INTERNAL_API_URL = backendUrl;
  });
});
