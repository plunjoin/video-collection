import React, { useState, useEffect } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import VideoCard from '../components/VideoCard';
import { getVideoDetail, type VideoRecord, type PlayGroup } from '../lib/api';

interface Props {
  id?: string;
  detail?: { video: VideoRecord; related: VideoRecord[] };
}

export default function AnimeDetailPage({ id = '317', detail: initialDetail }: Props) {
  const [detail, setDetail] = useState<{ video: VideoRecord; related: VideoRecord[] } | null>(
    initialDetail || null
  );
  const [loading, setLoading] = useState(!initialDetail);

  useEffect(() => {
    if (!initialDetail || (detail?.video && String(detail.video.id) !== String(id))) {
      setLoading(true);
      getVideoDetail(id)
        .then((res) => {
          if (res && res.video) setDetail(res);
        })
        .catch(() => {})
        .finally(() => setLoading(false));
    }
  }, [id]);

  if (loading) {
    return (
      <Layout title="正在载入番剧详情..." activeNav="番剧">
        <div className="py-24 text-center text-slate-400 text-sm">正在加载番剧档案...</div>
      </Layout>
    );
  }

  if (!detail || !detail.video) {
    return (
      <Layout title="未找到番剧" activeNav="番剧">
        <div className="py-24 text-center text-slate-400">
          <p>抱歉，未找到该番剧信息。</p>
          <a href="/category" className="mt-4 inline-block text-blue-500 font-medium">返回番剧库 →</a>
        </div>
      </Layout>
    );
  }

  const { video, related = [] } = detail;
  const playGroups: PlayGroup[] = video.play_groups || [];
  const episodes = playGroups[0]?.episodes || [];

  return (
    <Layout
      title={`${video.name} - bllii 番剧详情`}
      activeNav="番剧"
      description={`${video.name} 在线观看`}
      image={video.picture}
    >
      <div className="max-w-[1360px] mx-auto px-4 sm:px-6 pt-6 pb-16">
        {/* 顶部头部档案 */}
        <div className="bg-white rounded-3xl p-6 sm:p-8 shadow-sm border border-slate-100 flex flex-col md:flex-row gap-8 mb-8">
          <div className="w-48 sm:w-56 shrink-0 aspect-[3/4] rounded-2xl overflow-hidden shadow-md">
            <img
              src={video.picture || '/brand/bllii-app-blue.svg'}
              alt={video.name}
              className="w-full h-full object-cover"
              onError={(e) => {
                const target = e.currentTarget;
                target.onerror = null;
                target.src = '/brand/bllii-app-blue.svg';
              }}
            />
          </div>

          <div className="flex-1 flex flex-col justify-between">
            <div>
              <div className="flex items-center gap-3 mb-2">
                <span className="px-2.5 py-0.5 rounded-full text-xs font-semibold bg-blue-50 text-blue-600">
                  {video.type_name || '番剧'}
                </span>
                {video.remarks && (
                  <span className="text-xs text-slate-500 font-medium">{video.remarks}</span>
                )}
              </div>
              <h1 className="text-2xl sm:text-3xl font-bold text-slate-800 mb-3">{video.name}</h1>
              <p className="text-xs text-slate-500 mb-4 flex flex-wrap gap-x-4 gap-y-1">
                <span>地区：{video.area || '未知'}</span>
                <span>年份：{video.year || '未知'}</span>
                <span>语言：{video.language || '未知'}</span>
                {video.actor && <span>声优/演员：{video.actor}</span>}
                {video.director && <span>导演：{video.director}</span>}
              </p>

              <div className="text-xs text-slate-600 leading-relaxed max-w-3xl line-clamp-4">
                {video.content ? video.content.replace(/<[^>]+>/g, '') : '暂无详细剧情简介。'}
              </div>
            </div>

            <div className="pt-6 flex items-center gap-4">
              <a
                href={`/play/${video.id}`}
                className="px-6 py-3 rounded-2xl bg-[#597bea] hover:bg-[#4b6fd6] text-white font-semibold text-sm shadow-md transition-all flex items-center gap-2"
              >
                <BrandIcon name="play" size={18} />
                <span>立即播放</span>
              </a>
              <button
                type="button"
                className="px-5 py-3 rounded-2xl bg-slate-50 hover:bg-slate-100 text-slate-700 font-semibold text-sm border border-slate-200 transition-all flex items-center gap-2"
              >
                <BrandIcon name="heart" size={18} />
                <span>追番收藏</span>
              </button>
            </div>
          </div>
        </div>

        {/* 选集 */}
        {episodes.length > 0 && (
          <div className="bg-white rounded-3xl p-6 shadow-sm border border-slate-100 mb-8">
            <h2 className="text-base font-bold text-slate-800 mb-4">剧集列表 ({episodes.length}话)</h2>
            <div className="grid grid-cols-3 sm:grid-cols-6 md:grid-cols-8 gap-2.5">
              {episodes.map((ep, idx) => (
                <a
                  key={idx}
                  href={`/play/${video.id}?ep=${idx}`}
                  className="py-2.5 px-2 rounded-xl text-xs font-semibold bg-slate-50 hover:bg-blue-50 hover:text-blue-600 text-slate-700 text-center transition-all truncate border border-slate-100/80"
                  title={ep.name}
                >
                  {ep.name}
                </a>
              ))}
            </div>
          </div>
        )}

        {/* 相关推荐 */}
        {related.length > 0 && (
          <div className="mb-8">
            <div className="section-heading mb-4">
              <h2>同好推荐 <span>›</span></h2>
            </div>
            <div className="video-grid">
              {related.slice(0, 6).map((item) => (
                <VideoCard key={item.id} video={item} />
              ))}
            </div>
          </div>
        )}
      </div>
    </Layout>
  );
}
