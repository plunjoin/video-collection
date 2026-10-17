import type { APIRoute } from 'astro';
import { getVideos } from '../lib/api';
import { getSiteOrigin } from '../lib/site';

export const GET: APIRoute = async ({ site, url, request }) => {
  const domain = getSiteOrigin(site, url, request);
  const now = new Date().toISOString();

  // 基础静态频道
  const staticPages = [
    { loc: `${domain}/`, priority: '1.0', changefreq: 'daily' },
    { loc: `${domain}/category`, priority: '0.9', changefreq: 'daily' },
    { loc: `${domain}/rank`, priority: '0.8', changefreq: 'daily' },
    { loc: `${domain}/latest`, priority: '0.8', changefreq: 'daily' },
    { loc: `${domain}/news`, priority: '0.7', changefreq: 'weekly' },
    { loc: `${domain}/community`, priority: '0.7', changefreq: 'daily' },
  ];

  // 动态拉取前 300 部番剧以供爬虫全速收录
  let videoPages: { loc: string; lastmod: string; priority: string; changefreq: string; title: string; desc: string; thumb: string }[] = [];
  try {
    const res = await getVideos({ page: 1, pageSize: 300 });
    if (res && res.list) {
      videoPages = res.list.map(v => {
        const thumb = v.picture || v.pic || '/brand/bllii-app-blue.svg';
        const fullThumb = thumb.startsWith('http') ? thumb : `${domain}${thumb}`;
        const desc = (v.content || v.remarks || v.name).replace(/<[^>]+>/g, '').slice(0, 200);
        return {
          loc: `${domain}/anime/${v.id}`,
          lastmod: v.updated_at || v.created_at || now,
          priority: '0.8',
          changefreq: 'weekly',
          title: v.name,
          desc,
          thumb: fullThumb
        };
      });
    }
  } catch (e) {
    console.error('[Sitemap] Fetch videos error:', e);
  }

  const sitemapXml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:video="http://www.google.com/schemas/sitemap-video/1.1">
  ${staticPages
    .map(
      p => `
  <url>
    <loc>${p.loc}</loc>
    <lastmod>${now}</lastmod>
    <changefreq>${p.changefreq}</changefreq>
    <priority>${p.priority}</priority>
  </url>`
    )
    .join('')}
  ${videoPages
    .map(
      p => `
  <url>
    <loc>${p.loc}</loc>
    <lastmod>${p.lastmod}</lastmod>
    <changefreq>${p.changefreq}</changefreq>
    <priority>${p.priority}</priority>
    <video:video>
      <video:thumbnail_loc>${p.thumb}</video:thumbnail_loc>
      <video:title><![CDATA[${p.title}]]></video:title>
      <video:description><![CDATA[${p.desc}]]></video:description>
      <video:player_loc allow_embed="yes">${p.loc}</video:player_loc>
    </video:video>
  </url>`
    )
    .join('')}
</urlset>`;

  return new Response(sitemapXml.trim(), {
    headers: {
      'Content-Type': 'application/xml; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  });
};
