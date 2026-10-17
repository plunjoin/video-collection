import type { APIRoute } from 'astro';
import { getVideos } from '../lib/api';
import { getSiteOrigin } from '../lib/site';

export const GET: APIRoute = async ({ site, url, request }) => {
  const domain = getSiteOrigin(site, url, request);

  let topAnimeList = '';
  try {
    const res = await getVideos({ page: 1, pageSize: 30, sort: 'hits' });
    if (res && res.list && res.list.length > 0) {
      topAnimeList = res.list
        .map(v => {
          const desc = (v.content || v.remarks || '').replace(/<[^>]+>/g, '').slice(0, 100);
          return `- [${v.name}](${domain}/anime/${v.id}): ${v.type_name || '番剧'} | ${v.area || ''} | ${desc}`;
        })
        .join('\n');
    }
  } catch {
    // fallback
  }

  const content = `# Bllii · 影视与番剧智能聚合平台

> Bllii 是一个现代化的动漫番剧与影视在线浏览、选集播放与同好交流平台。

## 核心频道
- [首页](${domain}/): 精选番剧、最新更新推荐与热门合集
- [番剧库](${domain}/category): 多维度题材筛选（热血、恋爱、悬疑、科幻、奇幻、治愈等）
- [人气榜单](${domain}/rank): 全站热播榜、口碑榜与好评作品推荐
- [新番时间表](${domain}/latest): 每日番剧更新日历与追番进度同步
- [交流社区](${domain}/community): 追番心得、番剧讨论与漫迷社区

## 热门番剧与索引精选
${topAnimeList || '- 请访问网站首页与番剧库查看全量作品目录。'}

## 开发者与平台说明
- 平台提供 RESTful API，并支持 PWA 离线浏览与多端播放。
- 更多详细内容请访问：${domain}
`;

  return new Response(content, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'public, max-age=86400',
    },
  });
};
