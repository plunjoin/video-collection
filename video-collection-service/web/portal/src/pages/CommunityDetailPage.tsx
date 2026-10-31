import React, { useEffect, useState } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import MemberIdentity from '../components/MemberIdentity';
import Comments from '../components/Comments';
import { getCommunityPostDetail, togglePostLike, type ContentItem, type WikiSubjectBrief } from '../lib/api';
import { getToken } from '../lib/auth';

export default function CommunityDetailPage({ id }: { id: number }) {
  const [post, setPost] = useState<ContentItem | null>(null);
  const [authorSubject, setAuthorSubject] = useState<WikiSubjectBrief | null>(null);
  const [missing, setMissing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [commentDelta, setCommentDelta] = useState(0);

  useEffect(() => {
    let alive = true;
    getCommunityPostDetail(id).then((result) => {
      if (!alive) return;
      if (!result) {
        setMissing(true);
        return;
      }
      setPost(result.item);
      setAuthorSubject(result.authorSubject);
    });
    return () => { alive = false; };
  }, [id]);

  useEffect(() => {
    if (missing) window.location.replace('/community');
  }, [missing]);

  useEffect(() => {
    const onChanged = (event: Event) => {
      const detail = (event as CustomEvent<{ targetType: string; targetId: number; delta: number }>).detail;
      if (detail.targetType === 'post' && detail.targetId === id) setCommentDelta((prev) => prev + detail.delta);
    };
    window.addEventListener('comments-changed', onChanged);
    return () => window.removeEventListener('comments-changed', onChanged);
  }, [id]);

  const like = async () => {
    if (!post) return;
    if (!getToken()) {
      window.location.href = `/login?redirect=${encodeURIComponent(location.pathname)}`;
      return;
    }
    const liked = post.liked;
    setBusy(true);
    const result = await togglePostLike(id, !liked);
    if (result.ok) {
      setPost((prev) => prev ? {
        ...prev,
        liked: !liked,
        like_count: typeof result.like_count === 'number' ? result.like_count : prev.like_count + (liked ? -1 : 1),
      } : prev);
    }
    setBusy(false);
  };

  if (!post) {
    return (
      <Layout title="同好社区 — bllii" activeNav="社区">
        <div className="page-content" style={{ maxWidth: 880, minHeight: 220 }}></div>
      </Layout>
    );
  }

  return (
    <Layout title={`${post.title} — bllii 社区`} activeNav="社区">
      <div className="page-content" style={{ maxWidth: 880 }}>
        <a href="/community" className="news-back">‹ 返回社区</a>
        <article className="community-post community-post-detail">
          <div className="community-author">
            {authorSubject ? (
              <a
                href={`/wiki/${authorSubject.id}`}
                className="inline-flex items-center gap-1.5 hover:opacity-80"
                title={`查看 ${authorSubject.name} 的词条档案（作品、关系网络）`}
              >
                <MemberIdentity
                  name={post.author_name || '匿名用户'}
                  avatar={post.author_avatar}
                  frame={post.author_frame}
                  badge={post.author_badge}
                  color={post.author_color}
                  metadata={`${new Date(post.created_at).toLocaleString('zh-CN')}${post.category ? ` · ${post.category}` : ''}`}
                />
                <span className="text-[11px] font-semibold text-purple-500 bg-purple-50 border border-purple-100 rounded-full px-2 py-0.5">词条 ›</span>
              </a>
            ) : (
              <MemberIdentity
                name={post.author_name || '匿名用户'}
                avatar={post.author_avatar}
                frame={post.author_frame}
                badge={post.author_badge}
                color={post.author_color}
                metadata={`${new Date(post.created_at).toLocaleString('zh-CN')}${post.category ? ` · ${post.category}` : ''}`}
              />
            )}
            {post.pinned ? <span className="community-pin-badge">置顶</span> : null}
          </div>
          <h1>{post.title}</h1>
          {post.summary ? <p className="community-post-summary">{post.summary}</p> : null}
          <div className="community-post-content" style={{ whiteSpace: 'pre-wrap' }}>{post.content}</div>
          <footer>
            <button
              className="community-like-btn"
              data-liked={String(post.liked)}
              aria-label={post.liked ? '取消点赞帖子' : '点赞帖子'}
              onClick={like}
              disabled={busy}
            >
              <span className="like-icon"><BrandIcon name="heart" size={16} /></span>
              <span className="like-count">{post.like_count}</span>
            </button>
            <a href="#comments" className="community-meta-info">
              <BrandIcon name="message" size={16} />
              <span>{Math.max(0, post.comment_count + commentDelta)} 评论</span>
            </a>
          </footer>
        </article>
        <Comments targetType="post" targetId={post.id} />
      </div>
    </Layout>
  );
}
