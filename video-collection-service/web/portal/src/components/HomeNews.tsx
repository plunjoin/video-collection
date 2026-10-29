import React from 'react';
import type { ContentItem } from '../lib/api';

interface Props {
  items?: ContentItem[];
}

function fmtDate(d?: string): string {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return d;
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
}

export default function HomeNews({ items = [] }: Props) {
  return (
    <section className="brand-section home-news" aria-label="最新资讯">
      <div className="section-heading">
        <h2>最新资讯</h2>
        <a href="/news">更多 →</a>
      </div>
      {items.length > 0 ? (
        <div className="editorial-grid home-news-grid">
          {items.slice(0, 4).map((item) => (
            <a key={item.id} href={`/news/${item.id}`} className="editorial-card">
              {item.cover ? (
                <img 
                  src={item.cover} 
                  alt={item.title} 
                  loading="lazy" 
                  onError={(e) => { e.currentTarget.style.display = 'none'; }} 
                />
              ) : (
                <div className="editorial-card__placeholder">
                  <img src="/brand/bllii-symbol.svg" alt="" />
                </div>
              )}
              <div>
                <time>{fmtDate(item.published_at || item.created_at)}</time>
                {item.category && <span className="editorial-label">{item.category}</span>}
                <h2>{item.title}</h2>
                <p>{item.summary || '点击查看详情'}</p>
              </div>
            </a>
          ))}
        </div>
      ) : (
        <p className="brand-empty">
          暂无资讯，新鲜情报整理中。<a href="/news">去资讯页看看 →</a>
        </p>
      )}
    </section>
  );
}
