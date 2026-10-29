import React, { useState, useEffect } from 'react';
import Layout from '../layouts/Layout';
import { getRankings, type VideoRecord } from '../lib/api';

interface Props {
  initialTop?: VideoRecord[];
}

export default function RankPage({ initialTop }: Props) {
  const [top, setTop] = useState<VideoRecord[]>(initialTop || []);
  const [tab, setTab] = useState(0);

  useEffect(() => {
    if (top.length === 0) {
      getRankings()
        .then((res) => {
          setTop(res.top || []);
        })
        .catch(() => {});
    }
  }, []);

  const groups = [
    { label: '人气热播', list: top },
    {
      label: '最新作品',
      list: [...top].sort((a, b) => (parseInt(b.year) || 0) - (parseInt(a.year) || 0)),
    },
  ];

  const currentList = groups[tab]?.list || [];

  return (
    <Layout title="人气排行榜 — bllii" activeNav="排行榜">
      <div className="page-content max-w-[1360px] mx-auto px-4 sm:px-6 pt-6 pb-16">
        <div className="page-toolbar flex gap-2 mb-6" role="tablist" aria-label="榜单类型">
          {groups.map((group, i) => (
            <button
              key={group.label}
              type="button"
              onClick={() => setTab(i)}
              className={`page-pill px-4 py-2 rounded-xl text-xs font-semibold cursor-pointer transition-all ${
                tab === i ? 'bg-[#597bea] text-white shadow-sm' : 'bg-white text-slate-600 hover:bg-slate-50'
              }`}
            >
              {group.label}
            </button>
          ))}
        </div>

        <div className="ranking-list">
          {currentList.map((video, index) => (
            <article
              key={video.id}
              className="ranking-entry"
              data-track-expose
              data-track-id={video.id}
              data-track-rank={index + 1}
            >
              <span className="ranking-number">{String(index + 1).padStart(2, '0')}</span>
              <img
                src={video.picture || '/brand/bllii-app-light.svg'}
                alt={video.name}
                loading="lazy"
                onError={(e) => {
                  const target = e.currentTarget;
                  target.onerror = null;
                  target.src = '/brand/bllii-app-light.svg';
                }}
              />
              <div className="ranking-info">
                <h2>
                  <a href={`/anime/${video.id}`} data-track="video_click" data-track-id={video.id}>
                    {video.name}
                  </a>
                </h2>
                <p>{video.remarks || '更新中'} · {video.year || '番剧'}</p>
                <p>{video.type_name} · {video.area}</p>
              </div>
              <a
                className="brand-outline"
                href={`/play/${video.id}`}
                data-track="video_click"
                data-track-id={video.id}
              >
                立即观看 →
              </a>
            </article>
          ))}
        </div>

        {currentList.length === 0 && (
          <div className="page-empty text-center py-16 text-slate-400">
            <img src="/brand/bllii-symbol.svg" className="mx-auto w-16 mb-4 opacity-50" alt="" />
            <h2 className="text-base font-semibold text-slate-600">热爱正在汇集</h2>
            <p className="text-xs mt-1">暂时没有榜单数据，稍后再来看看。</p>
          </div>
        )}
      </div>
    </Layout>
  );
}
