/**
 * 获取站点的绝对基础 URL (100% 环境变量与请求驱动，无任何硬编码)
 * 优先级：
 * 1. 环境变量 SITE_URL / PUBLIC_SITE_URL
 * 2. 请求头 X-Forwarded-Proto + (X-Forwarded-Host || Host) 反向代理头
 * 3. Astro 配置中的 site
 * 4. 当前请求 URL origin
 */
export function getSiteOrigin(site?: URL, url?: URL, request?: Request): string {
  // 1. 优先读取环境变量配置
  const envUrl = (
    (typeof import.meta !== 'undefined' && import.meta.env && (import.meta.env.SITE_URL || import.meta.env.PUBLIC_SITE_URL)) ||
    (typeof process !== 'undefined' && process.env && (process.env.SITE_URL || process.env.PUBLIC_SITE_URL)) ||
    ''
  ).trim();

  if (envUrl) {
    return envUrl.replace(/\/$/, '');
  }

  // 2. 读取反向代理透传的真实请求头
  if (request) {
    const proto = request.headers.get('x-forwarded-proto') || 'https';
    const host = request.headers.get('x-forwarded-host') || request.headers.get('host');
    if (host) {
      return `${proto}://${host}`.replace(/\/$/, '');
    }
  }

  // 3. 读取 Astro site 配置
  if (site && site.origin) {
    return site.origin.replace(/\/$/, '');
  }

  // 4. 读取当前 URL origin
  if (url && url.origin) {
    return url.origin.replace(/\/$/, '');
  }

  return 'http://localhost:4321';
}
