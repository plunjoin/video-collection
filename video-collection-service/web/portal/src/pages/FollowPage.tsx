import React, { useState, useEffect } from 'react';
import Layout from '../layouts/Layout';
import { getAnimeVideos, type VideoRecord } from '../lib/api';
import { getToken } from '../lib/auth';

export default function FollowPage() {
  const [tab, setTab] = useState<'following' | 'history'>('following');
  const [followingList, setFollowingList] = useState<VideoRecord[]>([]);
  const [historyList, setHistoryList] = useState<any[]>([]);
  const [isLoggedIn, setIsLoggedIn] = useState(false);

  useEffect(() => {
    setIsLoggedIn(!!getToken());
    getAnimeVideos(12)
      .then((res) => {
        setFollowingList(res || []);
      })
      .catch(() => {});

    // 读取本地观看历史
    try {
      const saved = localStorage.getItem('bllii_play_history');
      if (saved) {
        setHistoryList(JSON.parse(saved));
      }
    } catch {}
  }, []);

  return (
    <Layout title="追番列表与我的收藏 - bllii" activeNav="追番">
      <div className="max-w-[1360px] mx-auto px-4 sm:px-6 pt-6 pb-16">
        <div className="mb-6 space-y-4">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div>
              <p className="text-xs text-slate-400 mt-1">云端多设备实时同步播放记录与追番状态</p>
            </div>

            {!isLoggedIn && (
              <div className="flex items-center gap-3 px-4 py-2 rounded-2xl bg-blue-50 border border-blue-200/60 shadow-sm text-xs">
                <span className="text-slate-600">当前处于未登录访客模式</span>
                <a
                  href="/login?redirect=/follow"
                  className="px-3 py-1 rounded-full bg-[#597bea] text-white font-semibold hover:bg-blue-600 transition-colors shadow-sm"
                >
                  立即登录同步
                </a>
              </div>
            )}
          </div>

          <div className="flex items-center gap-2.5">
            <button
              type="button"
              onClick={() => setTab('following')}
              className={`px-4 py-1.5 rounded-full text-xs font-semibold cursor-pointer transition-all ${
                tab === 'following'
                  ? 'bg-[#597bea] text-white shadow-sm'
                  : 'bg-white text-slate-600 hover:bg-slate-100 ring-1 ring-slate-200'
              }`}
            >
              正在追番 ({followingList.length})
            </button>
            <button
              type="button"
              onClick={() => setTab('history')}
              className={`px-4 py-1.5 rounded-full text-xs font-semibold cursor-pointer transition-all ${
                tab === 'history'
                  ? 'bg-[#597bea] text-white shadow-sm'
                  : 'bg-white text-slate-600 hover:bg-slate-100 ring-1 ring-slate-200'
              }`}
            >
              观看历史 ({historyList.length})
            </button>
          </div>
        </div>

        {tab === 'following' && (
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
            {followingList.map((anime) => (
              <a
                key={anime.id}
                href={`/play/${anime.id}`}
                className="anime-card group flex flex-col card-hover-effect"
              >
                <div className="relative aspect-[3/4] w-full rounded-2xl overflow-hidden bg-slate-200 shadow-sm group-hover:shadow-md transition-shadow">
                  <img
                    src={anime.picture || '/brand/bllii-app-blue.svg'}
                    alt={anime.name}
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                    onError={(e) => {
                      const target = e.currentTarget;
                      target.onerror = null;
                      target.src = '/brand/bllii-app-blue.svg';
                    }}
                  />
                  <span className="absolute top-2 right-2 px-2 py-0.5 rounded-full text-[11px] font-medium bg-emerald-600/90 text-white backdrop-blur-sm shadow-sm">
                    追番中
                  </span>
                </div>
                <div className="mt-2.5 px-0.5">
                  <h3 className="text-sm font-semibold text-slate-800 group-hover:text-primary-600 transition-colors line-clamp-1">
                    {anime.name}
                  </h3>
                  <p className="text-xs text-slate-400 mt-0.5 line-clamp-1">
                    {anime.remarks || '更新中'}
                  </p>
                </div>
              </a>
            ))}
          </div>
        )}

        {tab === 'history' && (
          <div>
            {historyList.length === 0 ? (
              <div className="text-center py-20 text-slate-400">
                <img src="/brand/bllii-symbol.svg" className="mx-auto w-16 mb-4 opacity-50" alt="" />
                <h2 className="text-base font-semibold text-slate-700">暂无观看历史</h2>
                <p className="text-xs mt-1">去发现一部喜欢的番剧吧！</p>
              </div>
            ) : (
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                {historyList.map((item, idx) => (
                  <a
                    key={idx}
                    href={`/play/${item.id}`}
                    className="anime-card group flex flex-col card-hover-effect"
                  >
                    <div className="relative aspect-[3/4] w-full rounded-2xl overflow-hidden bg-slate-200 shadow-sm">
                      <img
                        src={item.picture || '/brand/bllii-app-blue.svg'}
                        alt={item.name}
                        className="w-full h-full object-cover"
                      />
                    </div>
                    <div className="mt-2.5 px-0.5">
                      <h3 className="text-sm font-semibold text-slate-800 line-clamp-1">{item.name}</h3>
                      <p className="text-xs text-slate-400 mt-0.5">上次观看至第 {item.ep || 1} 集</p>
                    </div>
                  </a>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </Layout>
  );
}
