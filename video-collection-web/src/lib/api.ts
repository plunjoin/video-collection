// 真实数据交互客户端：深度直连 video-collection-api
// 100% 遵循接口返回的数据结构，无缝驱动前端页面

export interface Episode {
  name: string;
  url: string;
}

export interface PlayGroup {
  source_id?: string;
  source_name?: string;
  from?: string;
  player_code: string;
  server: string;
  note: string;
  episodes: Episode[];
}

export interface VideoRecord {
  id: number;
  name: string;
  sub_name: string;
  type_id: number;
  type_name: string;
  picture: string;
  pic?: string;
  actor: string;
  director: string;
  area: string;
  language: string;
  year: string;
  remarks: string;
  content: string;
  source_id?: string;
  source_ids?: string[];
  hits?: number;
  tags?: string[];
  created_at?: string;
  updated_at?: string;
  play_groups?: PlayGroup[];
  play_routes?: PlayGroup[];
}

export interface Category {
  id: number;
  pid: number;
  name: string;
  sort: number;
}

const rawBase = typeof window === 'undefined'
  ? (process.env.INTERNAL_API_URL || (process.env.PUBLIC_API_URL?.startsWith('http') ? process.env.PUBLIC_API_URL : 'http://localhost:80'))
  : (import.meta.env.PUBLIC_API_URL || '');

export const API_BASE_URL = rawBase;

// 清理文本中的 HTML 标签 (如 <p> 等)
export function cleanSynopsis(html?: string): string {
  if (!html) return '暂无剧情简介';
  return html
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// 标准化视频数据，并根据标题与简介智能解析多维题材标签
export function formatVideo(v: VideoRecord): VideoRecord {
  const cleanText = cleanSynopsis(v.content);

  // 智能推断番剧题材类型 (确保多维筛选 100% 精准匹配)
  const genres: string[] = [];
  const textToScan = `${v.name} ${cleanText} ${v.remarks || ''} ${v.sub_name || ''}`.toLowerCase();

  if (/热血|战斗|打斗|干架|少年|神帝|神尊|破天|武魂|逆天|觉醒|征程|斩|剑道|强者|斗破|遮天|英雄|战士|拳|霸|武/.test(textToScan)) {
    genres.push('热血');
  }
  if (/玄幻|修真|修仙|仙侠|宗门|沧元图|神帝|神尊|灵气|飞升|长生|凡人|洪荒|天尊|武动|至尊|元尊|妖神|九天/.test(textToScan)) {
    genres.push('玄幻');
    genres.push('修真');
  }
  if (/冒险|异世界|转生|魔王|旅途|勇者|迷宫|探索|地下城|寻宝|奇遇|猎人/.test(textToScan)) {
    genres.push('冒险');
  }
  if (/奇幻|魔法|恶魔|魔王|入魔|妖怪|神话|幻想|妖精|超自然|灵异/.test(textToScan)) {
    genres.push('奇幻');
  }
  if (/搞笑|喜剧|轻松|欢乐|幽默|沙雕|马戏团|吐槽|无厘头/.test(textToScan)) {
    genres.push('搞笑');
  }
  if (/科幻|未来|科技|星际|机甲|宇宙|战舰|仿生|元宇宙|赛博|末世/.test(textToScan)) {
    genres.push('科幻');
  }
  if (/治愈|温馨|日常|感动|陪伴|温暖|田园|治愈系|成长/.test(textToScan)) {
    genres.push('治愈');
  }
  if (/恋爱|纯爱|情侣|浪漫|甜蜜|假扮恋人|动了真心|少女|指尖浪漫|晴转恋|恋人|爱情/.test(textToScan)) {
    genres.push('恋爱');
  }
  if (/悬疑|推理|侦探|柯南|破案|密室|真相|凶手|死亡|游戏|秘密|解密|诡异/.test(textToScan)) {
    genres.push('悬疑');
  }

  return {
    ...v,
    content: cleanText,
    tags: Array.from(new Set([v.type_name || '番剧', ...genres])),
    picture: v.picture || v.pic || '',
    pic: v.pic || v.picture || '',
    play_groups: (v.play_groups || v.play_routes || []).map((g, idx) => ({
      ...g,
      server: g.source_name || (g.server && g.server !== 'no' ? g.server : `线路 ${idx + 1}`),
    })),
  };
}

async function apiFetch<T>(endpoint: string, options: RequestInit = {}): Promise<T | null> {
  const base = API_BASE_URL ? API_BASE_URL.replace(/\/$/, '') : '';
  const cleanEndpoint = endpoint.startsWith('/') ? endpoint : `/${endpoint}`;
  const url = base ? `${base}${cleanEndpoint}` : cleanEndpoint;
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 4000);
    const res = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
        'Accept': 'application/json',
        ...(options.headers || {})
      }
    });
    clearTimeout(timeoutId);

    if (!res.ok) {
      return null;
    }
    return await res.json() as T;
  } catch (e) {
    console.error(`[API Fetch Error] ${url}:`, e);
    return null;
  }
}

// 判断是否为纯正动漫作品
export function isAnimeRecord(v: VideoRecord): boolean {
  if (!v) return false;
  const typeId = Number(v.type_id);
  const typeName = v.type_name || '';
  if ([4, 15, 16, 17].includes(typeId)) return true;
  if (/动漫|动画|漫剧|动态漫/.test(typeName)) return true;
  return false;
}

// 1. 获取视频列表 (严格限定为动漫类型，完全基于后端 API)
export async function getVideos(params: { page?: number; pageSize?: number; typeId?: number; keyword?: string; area?: string; year?: string; sort?: string } = {}) {
  const { page = 1, pageSize = 24, typeId, keyword, area, year, sort } = params;
  const q = new URLSearchParams({
    page: String(page),
    page_size: String(pageSize),
  });

  // 严格保证只要动漫分类：若未指定或非动漫ID，默认使用动漫总类 type_id=4
  const validAnimeIds = [4, 15, 16, 17];
  const finalTypeId = (typeId && validAnimeIds.includes(typeId)) ? typeId : 4;
  q.set('type_id', String(finalTypeId));

  if (keyword) q.set('keyword', keyword);
  if (area && area !== '全部') q.set('area', area);
  if (year && year !== '全部') q.set('year', year);
  if (sort && sort !== 'time') q.set('sort', sort);

  const res = await apiFetch<{ code: number; total: number; data: VideoRecord[] }>(`/api/videos?${q.toString()}`);
  if (res && (res.code === 1 || res.code === 200) && res.data) {
    const list = res.data.filter(isAnimeRecord).map(formatVideo);
    return {
      total: res.total,
      list
    };
  }
  return { total: 0, list: [] };
}

// 获取全部动漫视频 (并行提取全量优质动漫作品，供给静态路由及前台推荐)
export async function getAllVideos(limit = 600): Promise<VideoRecord[]> {
  try {
    const pageCount = Math.ceil(limit / 100);
    const promises = [];
    for (let p = 1; p <= pageCount; p++) {
      promises.push(getVideos({ page: p, pageSize: 100, typeId: 4 }));
    }
    const results = await Promise.all(promises);
    const combined = results.flatMap(r => r.list).filter(isAnimeRecord);
    const map = new Map<number, VideoRecord>();
    for (const v of combined) {
      if (!map.has(v.id)) {
        map.set(v.id, v);
      }
    }
    return Array.from(map.values());
  } catch (e) {
    const fallback = await getVideos({ page: 1, pageSize: 50, typeId: 4 });
    return fallback.list.filter(isAnimeRecord);
  }
}

// 专门提取纯动漫作品 (按热度与更新排序，确保 Bllii 视觉与内容 100% 番剧化)
export async function getAnimeVideos(limit = 18): Promise<VideoRecord[]> {
  const all = await getAllVideos();
  const animes = all.filter(isAnimeRecord);

  // 优先排序：热度高的排在前列
  animes.sort((a, b) => {
    const hitsA = a.hits || 0;
    const hitsB = b.hits || 0;
    if (hitsB !== hitsA) return hitsB - hitsA;
    return b.id - a.id;
  });

  return animes.slice(0, limit);
}

// 2. 获取视频详情，未找到时返回 null
export async function getVideoDetail(id: number | string) {
  const numId = Number(id);
  if (!numId) return null;
  const res = await apiFetch<{ code: number; data: VideoRecord; related: VideoRecord[] }>(`/api/video?id=${numId}`);
  if (!res || res.code !== 1 || !res.data) return null;

  const relatedAnime = (res.related || []).filter(isAnimeRecord).map(formatVideo);
  const related = relatedAnime.length > 0 ? relatedAnime : (await getAnimeVideos(10)).filter(v => v.id !== numId);
  return {
    video: formatVideo(res.data),
    related: related.slice(0, 10)
  };
}

// 3. 获取排行榜数据 (直接请求 /api/rankings，严格保证为动漫专属榜单)
export async function getRankings() {
  const res = await apiFetch<{ code: number; top: VideoRecord[]; movies: VideoRecord[]; tv: VideoRecord[]; variety: VideoRecord[]; anime: VideoRecord[] }>('/api/rankings?limit=10');
  
  // Bllii 是专业番剧门户，排行榜优先呈现动漫专属热度榜 (res.anime)
  if (res && res.code === 1 && res.anime && res.anime.length > 0) {
    const animeTop = res.anime.filter(isAnimeRecord).map(formatVideo);
    return {
      top: animeTop,
      anime: animeTop
    };
  }

  // 兜底直接取最新热度动漫
  const fallback = await getAnimeVideos(10);
  return {
    top: fallback.slice(0, 5),
    anime: fallback
  };
}

// 4. 获取分类列表 (严格保留动漫分类及其子分类)
export async function getCategories() {
  const res = await apiFetch<{ code: number; data: Category[] }>('/api/categories');
  if (res && res.code === 1 && res.data && res.data.length > 0) {
    const animeCategories = res.data.filter(c => c.id === 4 || c.pid === 4 || c.name.includes('动漫'));
    return animeCategories;
  }
  return [];
}

// 5. 获取最新更新 (严格保证为纯动漫更新)
export async function getLatest() {
  const res = await apiFetch<{ code: number; total: number; today: VideoRecord[]; yesterday: VideoRecord[]; earlier: VideoRecord[] }>('/api/latest');
  if (!res || res.code !== 1) return { code: 0, total: 0, today: [], yesterday: [], earlier: [] };

  const today = (res.today || []).filter(isAnimeRecord).map(formatVideo);
  const yesterday = (res.yesterday || []).filter(isAnimeRecord).map(formatVideo);
  const earlier = (res.earlier || []).filter(isAnimeRecord).map(formatVideo);
  return {
    code: 1,
    total: today.length + yesterday.length + earlier.length,
    today,
    yesterday,
    earlier,
  };
}

// 6. 播放打点
export async function hitVideo(id: number | string) {
  try {
    await fetch(`${API_BASE_URL.replace(/\/$/, '')}/api/video/hit?id=${id}`, { method: 'POST' });
  } catch (e) {
    // ignore
  }
}

// 7. 站点全局配置 (友链、联系方式、免责声明等)
export interface FriendLink {
  name: string;
  url: string;
  description?: string;
}

export interface SiteConfig {
  site_name?: string;
  site_subtitle?: string;
  site_announcement?: string;
  site_notice_enabled?: string;
  site_keywords?: string;
  site_description?: string;
  site_friend_links?: string;
  site_contact_email?: string;
  site_contact_group?: string;
  site_disclaimer?: string;
  friend_links?: FriendLink[];
  [key: string]: any;
}

export const DEFAULT_SITE_CONFIG: SiteConfig = {
  site_name: 'Bllii 动漫聚合',
  site_subtitle: '追番库 • 让生活多一种可能',
  site_announcement: '欢迎访问Bllii二次元番剧聚合平台！全新升级流媒体视觉、极光画质增强引擎与全站新番排行榜已全面开启！',
  site_notice_enabled: '1',
  site_keywords: '高清动漫,番剧新番,日漫,国漫,免费在线观看,苹果CMS接口',
  site_description: 'Bllii致力于提供全面、快速的高清二次元番剧与动漫流媒体在线观看服务与智能聚合。',
  site_contact_email: '',
  site_contact_group: '',
  site_disclaimer: '【免责声明】本站所有视频资源均系第三方公开网络接口与网络爬虫自动检索聚合，本站服务器不存储、不制作、不上传任何视听节目及视频文件。若相关内容无意侵犯了贵司版权或合法权益，请通过上方联系方式提供权利证明与侵权链接，我们将在收到通知后24小时内断开相关播放解析并配合清理。本站提倡支持正版影视与动漫。',
  friend_links: [],
};

export async function getSiteConfig(): Promise<SiteConfig> {
  const res = await apiFetch<{ code: number; data: Record<string, string> }>('/api/site/config');
  if (res && res.code === 1 && res.data) {
    const data = res.data;
    let friendLinks: FriendLink[] = DEFAULT_SITE_CONFIG.friend_links || [];
    if (data.site_friend_links) {
      try {
        const parsed = JSON.parse(data.site_friend_links);
        if (Array.isArray(parsed) && parsed.length > 0) {
          friendLinks = parsed;
        }
      } catch (e) {
        // use default
      }
    }
    return {
      ...DEFAULT_SITE_CONFIG,
      ...data,
      friend_links: friendLinks,
    };
  }
  return DEFAULT_SITE_CONFIG;
}

// ==================== 资讯 & 社区接口 ====================

export interface ContentItem {
  id: number;
  kind: string;
  author_id: number;
  author_name: string;
  author_avatar: string;
  title: string;
  summary: string;
  content: string;
  cover: string;
  category: string;
  status: string;
  pinned: boolean;
  like_count: number;
  comment_count: number;
  liked: boolean;
  created_at: string;
  updated_at: string;
}

export interface ContentList {
  code: number;
  data: ContentItem[];
  total: number;
  page: number;
  page_size: number;
}

export interface CommunityCommentItem {
  id: number;
  target_type: string;
  target_id: number;
  post_id: number;
  parent_id: number;
  root_id: number;
  user_id: number;
  author_name: string;
  author_avatar: string;
  content: string;
  is_deleted: boolean;
  like_count: number;
  reply_count: number;
  liked: boolean;
  created_at: string;
}

// 8. 获取资讯列表
export async function getNewsList(params: { page?: number; pageSize?: number; keyword?: string; category?: string } = {}): Promise<ContentList> {
  const { page = 1, pageSize = 12, keyword, category } = params;
  const q = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
  if (keyword) q.set('keyword', keyword);
  if (category) q.set('category', category);
  const res = await apiFetch<ContentList>(`/api/news?${q.toString()}`);
  if (res && res.code === 1) return res;
  return { code: 0, data: [], total: 0, page, page_size: pageSize };
}

// 9. 获取资讯详情
export async function getNewsDetail(id: number): Promise<ContentItem | null> {
  const res = await apiFetch<{ code: number; data: ContentItem }>(`/api/news?id=${id}`);
  if (res && res.code === 1 && res.data) return res.data;
  return null;
}

// 10. 获取社区帖子列表
export async function getCommunityPosts(params: { page?: number; pageSize?: number; keyword?: string; category?: string } = {}): Promise<ContentList> {
  const { page = 1, pageSize = 10, keyword, category } = params;
  const q = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
  if (keyword) q.set('keyword', keyword);
  if (category) q.set('category', category);
  const res = await apiFetch<ContentList>(`/api/community/posts?${q.toString()}`);
  if (res && res.code === 1) return res;
  return { code: 0, data: [], total: 0, page, page_size: pageSize };
}

// 11. 获取社区帖子详情
export async function getCommunityPostDetail(id: number): Promise<ContentItem | null> {
  const res = await apiFetch<{ code: number; data: ContentItem }>(`/api/community/posts?id=${id}`);
  if (res && res.code === 1 && res.data) return res.data;
  return null;
}

// 12. 获取社区帖子评论列表
export async function getCommunityComments(postId: number, page = 1, pageSize = 20): Promise<{ data: CommunityCommentItem[]; total: number; page: number; page_size: number }> {
  const q = new URLSearchParams({ target_type: 'post', target_id: String(postId), page: String(page), page_size: String(pageSize) });
  const res = await apiFetch<{ code: number; data: CommunityCommentItem[]; total: number; page: number; page_size: number }>(`/api/comments?${q.toString()}`);
  if (res && res.code === 1) return res;
  return { data: [], total: 0, page, page_size: pageSize };
}

// --- 以下为需要登录鉴权的客户端操作 ---

function authHeaders(): Record<string, string> {
  if (typeof window === 'undefined') return {};
  const token = localStorage.getItem('Bllii_token');
  return token ? { 'Authorization': `Bearer ${token}` } : {};
}

// 13. 发布社区帖子
export async function createCommunityPost(data: { title: string; summary?: string; content: string; cover?: string; category?: string }): Promise<{ ok: boolean; msg: string; data?: ContentItem }> {
  try {
    const res = await fetch(`${API_BASE_URL.replace(/\/$/, '')}/api/community/posts`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...authHeaders() },
      body: JSON.stringify({ ...data, status: 'published' }),
    });
    const json = await res.json();
    return { ok: json.code === 1, msg: json.msg || json.error || '发布失败', data: json.data };
  } catch (e: any) {
    return { ok: false, msg: e.message || '网络错误' };
  }
}

// 14. 删除社区帖子
export async function deleteCommunityPost(id: number): Promise<boolean> {
  try {
    const res = await fetch(`${API_BASE_URL.replace(/\/$/, '')}/api/community/posts?id=${id}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });
    const json = await res.json();
    return json.code === 1;
  } catch {
    return false;
  }
}

// 15. 发表社区评论
export async function createCommunityComment(postId: number, content: string): Promise<{ ok: boolean; msg: string; data?: CommunityCommentItem }> {
  try {
    const res = await fetch('/api/comments', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...authHeaders() },
      body: JSON.stringify({ target_type: 'post', target_id: postId, content }),
    });
    const json = await res.json();
    return { ok: json.code === 1, msg: json.msg || json.error || '评论失败', data: json.data };
  } catch (e: any) {
    return { ok: false, msg: e.message || '网络错误' };
  }
}

// 16. 删除社区评论
export async function deleteCommunityComment(id: number): Promise<boolean> {
  try {
    const res = await fetch(`/api/comments?id=${id}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });
    const json = await res.json();
    return json.code === 1;
  } catch {
    return false;
  }
}

// 17. 点赞/取消点赞帖子
export async function togglePostLike(postId: number, liked: boolean): Promise<{ ok: boolean; like_count?: number }> {
  try {
    const base = API_BASE_URL.replace(/\/$/, '');
    const res = liked
      ? await fetch(`${base}/api/community/likes`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...authHeaders() }, body: JSON.stringify({ post_id: postId }) })
      : await fetch(`${base}/api/community/likes?post_id=${postId}`, { method: 'DELETE', headers: authHeaders() });
    const json = await res.json();
    if (json.code === 1 && json.data) return { ok: true, like_count: json.data.like_count };
    return { ok: false };
  } catch {
    return { ok: false };
  }
}

