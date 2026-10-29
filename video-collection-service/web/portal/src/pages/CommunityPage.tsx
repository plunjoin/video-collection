import React, { useEffect, useState } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import MemberIdentity from '../components/MemberIdentity';
import { getCommunityPosts, createCommunityPost, togglePostLike, type ContentItem } from '../lib/api';
import { getToken, getUser } from '../lib/auth';
import { memberAvatar } from '../lib/members';

function fmtDate(d: string): string {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return d;
  const now = new Date();
  const diff = Math.floor((now.getTime() - dt.getTime()) / 1000);
  if (diff < 60) return '刚刚';
  if (diff < 3600) return `${Math.floor(diff / 60)} 分钟前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 小时前`;
  if (diff < 604800) return `${Math.floor(diff / 86400)} 天前`;
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
}

const PAGE_SIZE = 10;

// goja（SSR）没有 URLSearchParams，手写解析保证服务端渲染安全
function readQuery(): { page: number; keyword: string } {
  if (typeof window === 'undefined') return { page: 1, keyword: '' };
  const search = window.location.search;
  const get = (key: string) => {
    const m = new RegExp(`[?&]${key}=([^&]*)`).exec(search);
    return m ? decodeURIComponent(m[1].replace(/\+/g, ' ')) : '';
  };
  return { page: Math.max(1, parseInt(get('page') || '1', 10) || 1), keyword: get('keyword') };
}

export default function CommunityPage() {
  const [{ page, keyword }] = useState(readQuery);

  const [posts, setPosts] = useState<ContentItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [signedIn, setSignedIn] = useState(Boolean(getToken() && getUser()));
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [category, setCategory] = useState('');
  const [alert, setAlert] = useState<{ text: string; ok: boolean } | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const user = signedIn ? getUser() : null;
  const member = user ? {
    name: user.nickname || user.username,
    avatar: user.avatar,
    frame: user.decorations?.frame,
    badge: user.decorations?.badge,
    color: user.decorations?.nickname_color,
  } : null;

  useEffect(() => {
    const onChanged = () => setSignedIn(Boolean(getToken() && getUser()));
    window.addEventListener('auth-changed', onChanged);
    return () => window.removeEventListener('auth-changed', onChanged);
  }, []);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    getCommunityPosts({ page, pageSize: PAGE_SIZE, keyword })
      .then((result) => {
        if (!alive) return;
        setPosts(result.data || []);
        setTotal(result.total || 0);
      })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [page, keyword]);

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  const like = async (post: ContentItem) => {
    if (!getToken()) {
      window.location.href = '/login?redirect=/community';
      return;
    }
    const liked = post.liked;
    setPosts((prev) => prev.map((item) => (item.id === post.id ? {
      ...item,
      liked: !liked,
      like_count: item.like_count + (liked ? -1 : 1),
    } : item)));
    const result = await togglePostLike(post.id, !liked);
    if (!result.ok) {
      setPosts((prev) => prev.map((item) => (item.id === post.id ? { ...item, liked, like_count: post.like_count } : item)));
    } else if (typeof result.like_count === 'number') {
      setPosts((prev) => prev.map((item) => (item.id === post.id ? { ...item, like_count: result.like_count! } : item)));
    }
  };

  const submit = async () => {
    const t = title.trim();
    const c = content.trim();
    if (!t || !c) {
      setAlert({ text: '标题和正文不能为空', ok: false });
      return;
    }
    setSubmitting(true);
    const result = await createCommunityPost({ title: t, content: c, category: category.trim() });
    if (result.ok) {
      if (result.pending) {
        setAlert({ text: result.msg, ok: true });
        setTitle('');
        setContent('');
      } else {
        window.location.reload();
      }
    } else {
      setAlert({ text: result.msg, ok: false });
    }
    setSubmitting(false);
  };

  const pageHref = (p: number) => `/community?page=${p}${keyword ? `&keyword=${encodeURIComponent(keyword)}` : ''}`;

  return (
    <Layout title="同好社区 — bllii" activeNav="社区">
      <div className="page-content">
        <div className="page-toolbar">
          <span className="page-pill" aria-pressed="true">同好广场</span>
          <span className="text-xs text-slate-400">分享你喜欢的番剧，遇见同好</span>
        </div>

        <div className="community-layout">
          <div>
            <div className="community-post-form">
              <div className="community-post-form__header">
                <img src={memberAvatar(member?.avatar)} alt="" className="community-post-form__avatar" />
                <div className="community-post-form__intro">
                  <strong>{member?.name || '游客'}</strong>
                  <small>{signedIn ? (user?.role === 'operator' ? '发布内容需经管理员审核' : '分享你喜欢的故事吧') : '登录后即可发布帖子，分享你的想法'}</small>
                </div>
                {!signedIn ? <a href="/login?redirect=/community" className="community-login-btn">去登录</a> : null}
              </div>
              {signedIn ? (
                <div className="community-post-form__body">
                  <input type="text" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="标题（必填）" className="community-input" maxLength={200} />
                  <textarea value={content} onChange={(e) => setContent(e.target.value)} placeholder="说点什么吧…" className="community-textarea" maxLength={50000} rows={4}></textarea>
                  <input type="text" value={category} onChange={(e) => setCategory(e.target.value)} placeholder="分类（可选，如：推荐/吐槽/求助）" className="community-input" maxLength={50} />
                  <div className="community-post-form__actions">
                    <button className="brand-button" onClick={submit} disabled={submitting}>{submitting ? '发布中…' : '发布帖子'}</button>
                    {alert ? <span className="community-alert" style={{ color: alert.ok ? '#059669' : '#e88080' }}>{alert.text}</span> : null}
                  </div>
                </div>
              ) : null}
            </div>

            <div>
              {!loading && posts.length === 0 ? (
                <div className="page-empty">
                  <img src="/brand/bllii-symbol.svg" alt="" />
                  <h2>{keyword ? '没有找到匹配的帖子' : '暂无讨论'}</h2>
                  <p>{keyword ? '换个关键词试试吧。' : '成为第一个发帖的人吧！'}</p>
                </div>
              ) : (
                posts.map((post) => (
                  <article key={post.id} className="community-post">
                    <div className="community-author">
                      <MemberIdentity
                        name={post.author_name || '匿名用户'}
                        avatar={post.author_avatar}
                        frame={post.author_frame}
                        badge={post.author_badge}
                        color={post.author_color}
                        metadata={`${fmtDate(post.created_at)}${post.category ? ` · ${post.category}` : ''}`}
                      />
                      {post.pinned ? <span className="community-pin-badge">置顶</span> : null}
                    </div>
                    <h2><a href={`/community/${post.id}`}>{post.title}</a></h2>
                    {post.summary ? <p className="community-post-summary">{post.summary}</p> : null}
                    <footer>
                      <button
                        className="community-like-btn"
                        data-liked={String(post.liked)}
                        aria-label={post.liked ? '取消点赞帖子' : '点赞帖子'}
                        onClick={() => like(post)}
                      >
                        <span className="like-icon"><BrandIcon name="heart" size={16} /></span>
                        <span className="like-count">{post.like_count}</span>
                      </button>
                      <a href={`/community/${post.id}`} className="community-comment-link">
                        <BrandIcon name="message" size={16} /> <span>{post.comment_count}</span> 评论
                      </a>
                      <a href={`/community/${post.id}`} className="community-read-more">查看详情 →</a>
                    </footer>
                  </article>
                ))
              )}
            </div>

            {totalPages > 1 ? (
              <div className="news-pagination">
                {page > 1 ? <a href={pageHref(page - 1)} className="news-page-btn">‹ 上一页</a> : null}
                <span className="news-page-info">{page} / {totalPages}</span>
                {page < totalPages ? <a href={pageHref(page + 1)} className="news-page-btn">下一页 ›</a> : null}
              </div>
            ) : null}
          </div>

          <aside className="community-aside">
            <h2>从共同的喜欢开始</h2>
            <a href="/category?genre=治愈"># 今天也需要一点治愈</a>
            <a href="/rank"># 大家都在追什么</a>
            <a href="/latest"># 最新更新速报</a>
            <img src="/brand/bllii-symbol.svg" alt="" />
            <p className="text-xs text-slate-400 leading-loose">MORE STORIES,<br />TOGETHER.</p>
          </aside>
        </div>
      </div>
    </Layout>
  );
}
