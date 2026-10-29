import React, { useState, useEffect } from 'react';
import Layout from '../layouts/Layout';
import VideoCard from '../components/VideoCard';
import { getLatest, type VideoRecord } from '../lib/api';

interface Props {
  initialData?: { today: VideoRecord[]; yesterday: VideoRecord[]; earlier: VideoRecord[] };
}

export default function LatestPage({ initialData }: Props) {
  const [data, setData] = useState<{ today: VideoRecord[]; yesterday: VideoRecord[]; earlier: VideoRecord[] }>(
    initialData || {
      today: [],
      yesterday: [],
      earlier: [],
    }
  );
  const [tab, setTab] = useState(0);

  useEffect(() => {
    if (!initialData || (data.today.length === 0 && data.yesterday.length === 0 && data.earlier.length === 0)) {
      getLatest()
        .then((res) => {
          setData({
            today: res.today || [],
            yesterday: res.yesterday || [],
            earlier: res.earlier || [],
          });
        })
        .catch(() => {});
    }
  }, []);

  const groups = [
    { label: '今天', list: data.today },
    { label: '昨天', list: data.yesterday },
    { label: '更早更新', list: data.earlier },
  ];

  const currentGroup = groups[tab] || groups[0];

  return (
    <Layout title="新番更新 — bllii" activeNav="新番时间表">
      <div className="page-content max-w-[1360px] mx-auto px-4 sm:px-6 pt-6 pb-16">
        <div className="page-toolbar flex gap-2 mb-6" role="tablist" aria-label="更新时间">
          {groups.map((group, i) => (
            <button
              key={group.label}
              type="button"
              onClick={() => setTab(i)}
              className={`page-pill px-4 py-2 rounded-xl text-xs font-semibold cursor-pointer transition-all ${
                tab === i ? 'bg-[#597bea] text-white shadow-sm' : 'bg-white text-slate-600 hover:bg-slate-50'
              }`}
            >
              {group.label} · {group.list.length}
            </button>
          ))}
        </div>

        <div>
          <p className="update-note mb-4 text-xs text-slate-400">
            {currentGroup.label}更新 · 好故事，慢慢追
          </p>
          <div className="video-grid">
            {currentGroup.list.map((video) => (
              <VideoCard key={video.id} video={video} badge={video.remarks || '更新'} />
            ))}
          </div>

          {!currentGroup.list.length && (
            <div className="page-empty text-center py-16 text-slate-400">
              <img src="/brand/bllii-symbol.svg" className="mx-auto w-16 mb-4 opacity-50" alt="" />
              <h2 className="text-base font-semibold text-slate-600">给期待一点时间</h2>
              <p className="text-xs mt-1">这段时间暂无更新，可以看看其他日期。</p>
            </div>
          )}
        </div>
      </div>
    </Layout>
  );
}
