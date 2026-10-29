import React, { useState, useEffect } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import { getVideos, type VideoRecord } from '../lib/api';

const channels = [
  { label: '全部动漫', value: '' },
  { label: '日韩动漫', value: '日韩' },
  { label: '国产动漫', value: '国产' },
  { label: '欧美动漫', value: '欧美' },
  { label: '动态漫画', value: '动态漫' },
];

const genres = ['全部', '热血', '玄幻', '修真', '冒险', '奇幻', '搞笑', '科幻', '治愈', '恋爱', '悬疑'];
const areas = ['全部', '日本', '大陆', '欧美', '韩国'];
const years = ['全部', '2026', '2025', '2024', '2023', '2022', '2021', '2020', '更早'];
const sorts = [
  { label: '按更新时间', value: 'time' },
  { label: '按综合评分', value: 'score' },
  { label: '按播放热度', value: 'hits' },
];

interface CategoryProps {
  initialVideos?: VideoRecord[];
  initialTotal?: number;
}

export default function CategoryPage({ initialVideos = [], initialTotal = 0 }: CategoryProps) {
  const [selectedChannel, setSelectedChannel] = useState('');
  const [selectedGenre, setSelectedGenre] = useState('');
  const [selectedArea, setSelectedArea] = useState('');
  const [selectedYear, setSelectedYear] = useState('');
  const [selectedSort, setSelectedSort] = useState('time');

  const [videos, setVideos] = useState<VideoRecord[]>(initialVideos);
  const [total, setTotal] = useState(initialTotal || initialVideos.length);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);

  const fetchList = (pageNum = 1) => {
    setLoading(true);
    getVideos({
      page: pageNum,
      pageSize: 24,
      keyword: selectedGenre && selectedGenre !== '全部' ? selectedGenre : undefined,
    })
      .then((res) => {
        let list = res.list || [];
        if (selectedChannel) {
          list = list.filter((v) => (v.type_name || '').includes(selectedChannel) || (v.name || '').includes(selectedChannel));
        }
        if (selectedArea && selectedArea !== '全部') {
          list = list.filter((v) => v.area?.includes(selectedArea));
        }
        if (selectedYear && selectedYear !== '全部') {
          list = list.filter((v) => v.year?.includes(selectedYear));
        }
        if (selectedSort === 'hits') {
          list = [...list].sort((a, b) => (b.hits || 0) - (a.hits || 0));
        }
        setVideos(list);
        setTotal(res.total || list.length);
        setPage(pageNum);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    if (videos.length === 0 || selectedChannel || (selectedGenre && selectedGenre !== '全部') || (selectedArea && selectedArea !== '全部') || (selectedYear && selectedYear !== '全部') || selectedSort !== 'time') {
      fetchList(1);
    }
  }, [selectedChannel, selectedGenre, selectedArea, selectedYear, selectedSort]);

  const resetFilters = () => {
    setSelectedChannel('');
    setSelectedGenre('');
    setSelectedArea('');
    setSelectedYear('');
    setSelectedSort('time');
  };

  const hasFilter = selectedChannel || selectedGenre || selectedArea || selectedYear || selectedSort !== 'time';

  return (
    <Layout title="番剧库 - bllii 分类索引" activeNav="番剧">
      <div className="max-w-[1360px] mx-auto px-4 sm:px-6 pt-6 pb-16">
        {/* 筛选面板卡片 */}
        <div className="bg-white rounded-2xl p-5 shadow-sm border border-slate-100/80 space-y-4 mb-6">
          {/* 1. 频道 */}
          <div className="flex items-center gap-3 text-xs sm:text-sm">
            <span className="text-slate-400 font-medium shrink-0 w-12">频道：</span>
            <div className="flex items-center gap-2 flex-wrap">
              {channels.map((ch) => (
                <button
                  key={ch.label}
                  type="button"
                  onClick={() => setSelectedChannel(ch.value)}
                  className={`px-3.5 py-1 rounded-full text-xs font-semibold transition-all cursor-pointer ${
                    selectedChannel === ch.value
                      ? 'bg-[#597bea] text-white shadow-sm shadow-blue-500/20'
                      : 'bg-slate-50 text-slate-600 hover:bg-slate-100'
                  }`}
                >
                  {ch.label}
                </button>
              ))}
            </div>
          </div>

          {/* 2. 类型 */}
          <div className="flex items-center gap-3 text-xs sm:text-sm">
            <span className="text-slate-400 font-medium shrink-0 w-12">类型：</span>
            <div className="flex items-center gap-2 flex-wrap">
              {genres.map((g, idx) => {
                const val = idx === 0 ? '' : g;
                return (
                  <button
                    key={g}
                    type="button"
                    onClick={() => setSelectedGenre(val)}
                    className={`px-3.5 py-1 rounded-full text-xs font-semibold transition-all cursor-pointer ${
                      selectedGenre === val
                        ? 'bg-[#597bea] text-white shadow-sm shadow-blue-500/20'
                        : 'bg-slate-50 text-slate-600 hover:bg-slate-100'
                    }`}
                  >
                    {g}
                  </button>
                );
              })}
            </div>
          </div>

          {/* 3. 地区 */}
          <div className="flex items-center gap-3 text-xs sm:text-sm">
            <span className="text-slate-400 font-medium shrink-0 w-12">地区：</span>
            <div className="flex items-center gap-2 flex-wrap">
              {areas.map((a, idx) => {
                const val = idx === 0 ? '' : a;
                return (
                  <button
                    key={a}
                    type="button"
                    onClick={() => setSelectedArea(val)}
                    className={`px-3.5 py-1 rounded-full text-xs font-semibold transition-all cursor-pointer ${
                      selectedArea === val
                        ? 'bg-[#597bea] text-white shadow-sm shadow-blue-500/20'
                        : 'bg-slate-50 text-slate-600 hover:bg-slate-100'
                    }`}
                  >
                    {a}
                  </button>
                );
              })}
            </div>
          </div>

          {/* 4. 年份 */}
          <div className="flex items-center gap-3 text-xs sm:text-sm">
            <span className="text-slate-400 font-medium shrink-0 w-12">年份：</span>
            <div className="flex items-center gap-2 flex-wrap">
              {years.map((y, idx) => {
                const val = idx === 0 ? '' : y;
                return (
                  <button
                    key={y}
                    type="button"
                    onClick={() => setSelectedYear(val)}
                    className={`px-3.5 py-1 rounded-full text-xs font-semibold transition-all cursor-pointer ${
                      selectedYear === val
                        ? 'bg-[#597bea] text-white shadow-sm shadow-blue-500/20'
                        : 'bg-slate-50 text-slate-600 hover:bg-slate-100'
                    }`}
                  >
                    {y}
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        {/* 排序与统计 */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5">
          <div className="flex items-center gap-2">
            {sorts.map((s) => (
              <button
                key={s.value}
                type="button"
                onClick={() => setSelectedSort(s.value)}
                className={`px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all cursor-pointer ${
                  selectedSort === s.value
                    ? 'bg-white shadow-sm text-[#597bea] ring-1 ring-blue-200'
                    : 'text-slate-500 hover:text-slate-800'
                }`}
              >
                {s.label}
              </button>
            ))}
          </div>

          <div className="flex items-center gap-3 text-xs text-slate-400">
            <span className="font-medium text-slate-600">
              共筛选出 <span className="text-[#597bea] font-bold">{String(total)}</span> 部作品
            </span>
            {hasFilter && (
              <button
                type="button"
                onClick={resetFilters}
                className="text-[#597bea] font-medium hover:underline cursor-pointer"
              >
                重置全部条件
              </button>
            )}
          </div>
        </div>

        {/* 卡片网格 */}
        <div className="relative min-h-[400px]">
          {loading && (
            <div className="py-12 text-center text-slate-400 text-xs">加载中...</div>
          )}
          {!loading && videos.length === 0 && (
            <div className="py-16 text-center text-slate-400">
              <p>暂无符合筛选条件的番剧作品</p>
            </div>
          )}
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
            {videos.map((anime, idx) => (
              <a
                key={anime.id}
                href={`/play/${anime.id}`}
                className="anime-card group flex flex-col card-hover-effect"
                data-track="video_click"
                data-track-id={anime.id}
                data-track-rank={idx + 1}
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
                    {[anime.year, anime.area, anime.type_name].filter(Boolean).join(' · ')}
                  </p>
                </div>
              </a>
            ))}
          </div>

          {/* 分页控制 */}
          {total > 24 && (
            <div className="flex items-center justify-center gap-3 pt-10">
              <button
                type="button"
                disabled={page <= 1}
                onClick={() => fetchList(page - 1)}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-white border border-slate-200 text-slate-600 disabled:opacity-40 cursor-pointer"
              >
                上一页
              </button>
              <span className="text-xs text-slate-500 font-medium">第 {page} 页</span>
              <button
                type="button"
                disabled={videos.length < 24}
                onClick={() => fetchList(page + 1)}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-white border border-slate-200 text-slate-600 disabled:opacity-40 cursor-pointer"
              >
                下一页
              </button>
            </div>
          )}
        </div>
      </div>
    </Layout>
  );
}
