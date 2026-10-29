import React, { useState, useEffect } from 'react';
import type { VideoRecord } from '../lib/api';

export default function ForYou() {
  const [items, setItems] = useState<VideoRecord[]>([]);
  const [basedOn, setBasedOn] = useState<string[]>([]);
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let token = '';
    try {
      token = localStorage.getItem('Bllii_token') || '';
    } catch {}

    if (!token) {
      setIsLoggedIn(false);
      setLoaded(true);
      return;
    }

    setIsLoggedIn(true);
    fetch('/api/recommend/for-you?limit=12', {
      headers: { Authorization: 'Bearer ' + token }
    })
      .then((res) => res.json())
      .then((json) => {
        const payload = (json && json.data) || {};
        setItems(payload.items || []);
        if (payload.based_on) setBasedOn(payload.based_on);
      })
      .catch(() => {})
      .finally(() => setLoaded(true));
  }, []);

  if (!loaded) return null;

  if (!isLoggedIn) {
    return (
      <div className="brand-section">
        <div className="for-you-hint">
          <span className="for-you-hint__text">登录后解锁「为你推荐」，首页只放你想看的</span>
          <a className="for-you-hint__action" href="/login">立即登录 →</a>
        </div>
      </div>
    );
  }

  return (
    <section id="for-you" className="brand-section">
      <div className="section-heading section-heading--wrap">
        <h2>为你推荐</h2>
        {basedOn.length > 0 && (
          <span className="text-xs text-slate-400">
            根据你的口味：{basedOn.join(' / ')}
          </span>
        )}
      </div>
      {items.length > 0 ? (
        <div className="video-grid">
          {items.map((anime) => (
            <a 
              key={anime.id}
              href={`/play/${anime.id}`} 
              className="anime-item group flex flex-col card-hover-effect"
              data-track="rec_click" 
              data-track-id={anime.id}
            >
              <div className="relative aspect-[3/4] w-full rounded-2xl overflow-hidden bg-slate-200 shadow-sm group-hover:shadow-md transition-shadow">
                <img
                  src={anime.picture || anime.pic || '/brand/bllii-app-blue.svg'}
                  alt={anime.name}
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                  loading="lazy"
                  onError={(e) => {
                    const target = e.currentTarget;
                    target.onerror = null;
                    target.src = '/brand/bllii-app-blue.svg';
                  }}
                />
                {anime.remarks && (
                  <span className="absolute top-2 right-2 px-2 py-0.5 rounded-full text-[11px] font-medium bg-[#597bea] text-white backdrop-blur-sm">
                    {anime.remarks}
                  </span>
                )}
              </div>
              <div className="mt-2.5 px-0.5">
                <h3 className="text-sm font-semibold text-slate-800 group-hover:text-primary-600 transition-colors line-clamp-1">
                  {anime.name}
                </h3>
                <p className="text-xs text-slate-400 mt-0.5 line-clamp-1">
                  {anime.actor || anime.type_name || '动漫'}
                </p>
              </div>
            </a>
          ))}
        </div>
      ) : (
        <p className="brand-empty">暂时没有专属推荐。多看几部喜欢的番剧，这里就会越来越懂你。</p>
      )}
    </section>
  );
}
