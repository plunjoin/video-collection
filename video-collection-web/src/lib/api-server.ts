// 与服务端页面取数共用后端地址；Node 启动时可通过环境变量覆盖。
export function getInternalApiUrl(): string {
  return process.env.INTERNAL_API_URL
    || (process.env.PUBLIC_API_URL?.startsWith('http') ? process.env.PUBLIC_API_URL : '')
    || 'http://localhost:80';
}

const hopByHopHeaders = [
  'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
  'te', 'trailer', 'transfer-encoding', 'upgrade',
];

function removeHopByHopHeaders(headers: Headers) {
  const connectionHeaders = headers.get('connection')?.split(',') || [];
  for (const name of [...hopByHopHeaders, ...connectionHeaders]) {
    if (name.trim()) headers.delete(name.trim());
  }
}

export async function proxyApiRequest(request: Request): Promise<Response> {
  try {
    const incoming = new URL(request.url);
    const target = new URL(getInternalApiUrl());
    target.pathname = target.pathname.replace(/\/$/, '') + incoming.pathname;
    target.search = incoming.search;

    const headers = new Headers(request.headers);
    removeHopByHopHeaders(headers);
    headers.delete('host');
    headers.delete('content-length');
    // fetch 自动解压响应，避免向浏览器转发不匹配的压缩头。
    headers.set('accept-encoding', 'identity');

    const options: RequestInit & { duplex?: 'half' } = {
      method: request.method,
      headers,
      redirect: 'manual',
      signal: AbortSignal.any([request.signal, AbortSignal.timeout(60_000)]),
    };
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      options.body = request.body;
      options.duplex = 'half';
    }

    const upstream = await fetch(target, options);
    const responseHeaders = new Headers(upstream.headers);
    removeHopByHopHeaders(responseHeaders);
    responseHeaders.delete('content-encoding');
    responseHeaders.delete('content-length');
    responseHeaders.delete('set-cookie');
    for (const cookie of upstream.headers.getSetCookie()) {
      responseHeaders.append('set-cookie', cookie);
    }

    // 保留后端响应类型并流式转发。
    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  } catch (error) {
    console.error('[API Proxy Error]', error);
    return Response.json({ code: 0, error: '无法连接后端 API，请检查服务及 INTERNAL_API_URL 配置' }, {
      status: 502,
    });
  }
}
