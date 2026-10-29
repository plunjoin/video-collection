import React, { useEffect, useState } from 'react';
import Layout from '../layouts/Layout';
import MemberIdentity from '../components/MemberIdentity';
import Comments from '../components/Comments';
import BrandIcon from '../components/BrandIcon';
import { getNewsDetail, type ContentItem } from '../lib/api';

function fmtDate(d?: string): string {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return d;
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')} ${String(dt.getHours()).padStart(2, '0')}:${String(dt.getMinutes()).padStart(2, '0')}`;
}

export default function NewsDetailPage({ id }: { id: number }) {
  const [item, setItem] = useState<ContentItem | null>(null);
  const [missing, setMissing] = useState(false);

  useEffect(() => {
    let alive = true;
    getNewsDetail(id).then((result) => {
      if (!alive) return;
      if (!result) setMissing(true);
      else setItem(result);
    });
    return () => { alive = false; };
  }, [id]);

  useEffect(() => {
    if (missing) window.location.replace('/news');
  }, [missing]);

  if (!item) {
    return (
      <Layout title="资讯 — bllii" activeNav="资讯">
        <div className="page-content" style={{ minHeight: 220 }}></div>
      </Layout>
    );
  }

  return (
    <Layout title={`${item.title} — bllii`} activeNav="资讯">
      <div className="page-content">
        <a href="/news" className="news-back">‹ 返回资讯列表</a>

        <article className="news-article">
          {item.category ? <span className="editorial-label">{item.category}</span> : null}
          <h1>{item.title}</h1>
          <div className="news-meta">
            {item.author_name ? (
              <MemberIdentity
                name={item.author_name}
                avatar={item.author_avatar}
                frame={item.author_frame}
                badge={item.author_badge}
                color={item.author_color}
              />
            ) : null}
            <time>{fmtDate(item.published_at || item.created_at)}</time>
            {item.like_count > 0 ? <span><BrandIcon name="heart" size={14} /> {item.like_count}</span> : null}
          </div>

          {item.cover ? (
            <img
              src={item.cover}
              alt={item.title}
              className="news-cover"
              onError={(event) => { const img = event.currentTarget; img.onerror = null; img.style.display = 'none'; }}
            />
          ) : null}

          {item.summary ? <p className="news-summary">{item.summary}</p> : null}

          <div className="news-body" style={{ whiteSpace: 'pre-wrap' }}>{item.content}</div>
        </article>
        <Comments targetType="news" targetId={item.id} />
      </div>
    </Layout>
  );
}
