import React, { useState, useEffect } from 'react';

interface Props {
  slot: 'banner' | 'home_recommend' | 'detail';
  limit?: number;
  inline?: boolean;
  className?: string;
  dataTags?: string;
}

interface AdItem {
  id: number;
  title: string;
  image: string;
  link?: string;
  video_id?: number;
}

function resolveHref(ad: AdItem) {
  const link = (ad.link || '').trim();
  if (link) return link;
  if (ad.video_id && ad.video_id > 0) return '/play/' + ad.video_id;
  return '';
}

export default function AdSlot({
  slot,
  limit = 1,
  inline = false,
  className = '',
  dataTags
}: Props) {
  const [ads, setAds] = useState<AdItem[]>([]);

  useEffect(() => {
    fetch('/api/ads?slot=' + encodeURIComponent(slot))
      .then((res) => res.json())
      .then((json) => {
        const list = ((json && json.data) || []).filter((ad: any) => ad && ad.image);
        if (list.length > 0) {
          setAds(list.slice(0, limit));
        }
      })
      .catch(() => {});
  }, [slot, limit]);

  if (!ads.length) return null;

  if (inline) {
    return (
      <div className={`ad-slot ad-slot--inline ${className}`.trim()} data-tags={dataTags}>
        {ads.map((ad) => {
          const href = resolveHref(ad) || '/category';
          const isExternal = href.startsWith('http');
          return (
            <a
              key={ad.id}
              href={href}
              target={isExternal ? '_blank' : undefined}
              rel={isExternal ? 'sponsored noopener' : undefined}
              className="anime-item group flex flex-col card-hover-effect ad-card"
              data-track="ad_click"
              data-track-id={ad.id}
            >
              <div className="relative aspect-[3/4] w-full rounded-2xl overflow-hidden bg-slate-200 shadow-sm group-hover:shadow-md transition-shadow">
                <img
                  src={ad.image}
                  alt={ad.title}
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                  loading="lazy"
                  onError={(e) => { e.currentTarget.style.display = 'none'; }}
                />
                <span className="absolute top-2 left-2 px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-black/45 text-white backdrop-blur-sm">
                  广告
                </span>
                {ad.title && (
                  <span className="absolute bottom-0 left-0 right-0 px-2 py-1.5 text-[11px] text-white bg-gradient-to-t from-black/60 to-transparent line-clamp-1">
                    {ad.title}
                  </span>
                )}
              </div>
              <div className="mt-2.5 px-0.5">
                <h3 className="text-sm font-semibold text-slate-800 group-hover:text-primary-600 transition-colors line-clamp-1">
                  {ad.title || '推广'}
                </h3>
                <p className="text-xs text-slate-400 mt-0.5 line-clamp-1">推广内容</p>
              </div>
            </a>
          );
        })}
      </div>
    );
  }

  return (
    <div className={`ad-slot ${className}`.trim()} data-tags={dataTags}>
      {ads.map((ad) => {
        const href = resolveHref(ad);
        if (!href) return null;
        const isExternal = href.startsWith('http');
        return (
          <a
            key={ad.id}
            href={href}
            target={isExternal ? '_blank' : undefined}
            rel={isExternal ? 'sponsored noopener' : undefined}
            className="ad-banner"
            data-track="ad_click"
            data-track-id={ad.id}
          >
            <img src={ad.image} alt={ad.title} className="ad-banner__img" loading="lazy" />
            <span className="ad-banner__tag">广告</span>
            {ad.title && <span className="ad-banner__title">{ad.title}</span>}
          </a>
        );
      })}
    </div>
  );
}
