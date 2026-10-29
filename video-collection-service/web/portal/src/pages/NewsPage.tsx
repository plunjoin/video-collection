import React, { useState, useEffect } from 'react';
import Layout from '../layouts/Layout';
import { getNewsList, type ContentItem } from '../lib/api';

function fmtDate(d?: string): string {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return d;
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
}

export default function NewsPage() {
  const [items, setItems] = useState<ContentItem[]>([]);
  const [total, setTotal] = useState(0);
  const [category, setCategory] = useState('');
  const [keyword, setKeyword] = useState('');
  const [loading, setLoading] = useState(false);

  const fetchNews = () => {
    setLoading(true);
    getNewsList({ page: 1, pageSize: 12, keyword: keyword || undefined, category: category || undefined })
      .then((res) => {
        setItems(res.data || []);
        setTotal(res.total || 0);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchNews();
  }, [category]);

  const categories = ['情报', '新番', '推荐', '访谈'];

  return (
    <Layout title="动漫资讯 — bllii" activeNav="资讯">
      <div className="page-content max-w-[1360px] mx-auto px-4 sm:px-6 pt-6 pb-16">
        {/* 顶部分类筛选 */}
        <div className="page-toolbar flex gap-2 mb-6">
          <button
            type="button"
            onClick={() => setCategory('')}
            className={`px-4 py-1.5 rounded-full text-xs font-semibold cursor-pointer transition-all ${
              !category ? 'bg-[#597bea] text-white shadow-sm' : 'bg-white text-slate-600 hover:bg-slate-50'
            }`}
          >
            全部
          </button>
          {categories.map((cat) => (
            <button
              key={cat}
              type="button"
              onClick={() => setCategory(cat)}
              className={`px-4 py-1.5 rounded-full text-xs font-semibold cursor-pointer transition-all ${
                category === cat ? 'bg-[#597bea] text-white shadow-sm' : 'bg-white text-slate-600 hover:bg-slate-50'
              }`}
            >
              {cat}
            </button>
          ))}
        </div>

        {/* 资讯列表 */}
        {loading && (
          <div className="py-16 text-center text-slate-400 text-xs">正在载入资讯...</div>
        )}

        {!loading && items.length === 0 && (
          <div className="text-center py-20 text-slate-400">
            <img src="/brand/bllii-symbol.svg" className="mx-auto w-16 mb-4 opacity-50" alt="" />
            <h2 className="text-base font-semibold text-slate-700">暂无资讯内容</h2>
          </div>
        )}

        {!loading && items.length > 0 && (
          <div className="editorial-grid">
            {items.map((item) => (
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
        )}
      </div>
    </Layout>
  );
}
