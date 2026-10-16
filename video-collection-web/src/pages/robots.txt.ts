import type { APIRoute } from 'astro';

export const GET: APIRoute = ({ site, url }) => {
  const domain = site ? site.toString().replace(/\/$/, '') : url.origin;
  const sitemapUrl = `${domain}/sitemap.xml`;

  const robots = `# Bllii Robots.txt
User-agent: *
Allow: /
Disallow: /api/
Disallow: /admin/
Disallow: /login
Disallow: /notifications

# Google & Major Search Engines
User-agent: Googlebot
Allow: /
User-agent: Googlebot-Video
Allow: /
User-agent: Bingbot
Allow: /

# GEO / AI Search Bots (放行 AI 搜索引擎爬虫以优化 GEO 收录)
User-agent: GPTBot
Allow: /
User-agent: PerplexityBot
Allow: /
User-agent: ClaudeBot
Allow: /
User-agent: Applebot-Extended
Allow: /
User-agent: CCBot
Allow: /

# Sitemap
Sitemap: ${sitemapUrl}
`;

  return new Response(robots, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'public, max-age=86400',
    },
  });
};
