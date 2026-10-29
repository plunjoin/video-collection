import React, { useState, useEffect } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import VideoCard from '../components/VideoCard';
import { getVideos, type VideoRecord } from '../lib/api';

export default function SearchPage() {
  const [keyword, setKeyword] = useState('');
  const [results, setResults] = useState<VideoRecord[]>([]);
  const [hotVideos, setHotVideos] = useState<VideoRecord[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);

  useEffect(() => {
    // 从 URL query 中取 q
    const params = new URLSearchParams(window.location.search);
    const q = params.get('q');
    if (q) {
      setKeyword(q);
      doSearch(q);
    }

    getVideos({ page: 1, pageSize: 6 })
      .then((res) => {
        setHotVideos(res.list || []);
      })
      .catch(() => {});
  }, []);

  const doSearch = (query: string) => {
    if (!query.trim()) return;
    setLoading(true);
    setSearched(true);
    getVideos({ page: 1, pageSize: 36, keyword: query.trim() })
      .then((res) => {
        setResults(res.list || []);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    doSearch(keyword);
  };

  return (
    <Layout title="番剧搜索 - bllii" activeNav="首页">
      <div className="max-w-[1360px] mx-auto px-4 sm:px-6 pt-6 pb-16">
        <div className="max-w-2xl mx-auto mb-8 text-center space-y-4">
          <form onSubmit={handleSubmit} className="relative">
            <input
              type="text"
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
              placeholder="请输入想看的番剧名称、角色或声优..."
              className="w-full h-12 pl-5 pr-28 rounded-full bg-white text-sm text-slate-800 shadow-sm border border-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-[#597bea] transition-all"
            />
            <button
              type="submit"
              className="absolute right-1.5 top-1.5 bottom-1.5 px-6 rounded-full bg-[#597bea] hover:bg-blue-600 text-white text-sm font-semibold transition-colors cursor-pointer"
            >
              搜索
            </button>
          </form>

          {hotVideos.length > 0 && (
            <div className="flex items-center justify-center gap-2 text-xs text-slate-400 flex-wrap">
              <span>热搜：</span>
              {hotVideos.map((anime) => (
                <button
                  key={anime.id}
                  type="button"
                  onClick={() => {
                    setKeyword(anime.name);
                    doSearch(anime.name);
                  }}
                  className="text-slate-600 hover:text-blue-600 hover:underline cursor-pointer"
                >
                  {anime.name}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* 结果列表 */}
        {loading && (
          <div className="py-16 text-center text-slate-400 text-xs">正在搜索番剧...</div>
        )}

        {!loading && searched && results.length === 0 && (
          <div className="py-20 text-center text-slate-400">
            <img src="/brand/bllii-symbol.svg" className="mx-auto w-16 mb-4 opacity-50" alt="" />
            <h2 className="text-base font-semibold text-slate-700">没有找到相关故事</h2>
            <p className="text-xs mt-1">换个关键词试试，或去番剧库发现精彩。</p>
          </div>
        )}

        {!loading && results.length > 0 && (
          <div>
            <div className="text-xs text-slate-500 mb-4">
              找到 <span className="font-bold text-blue-600">{results.length}</span> 部与 “{keyword}” 相关的番剧
            </div>
            <div className="video-grid">
              {results.map((video) => (
                <VideoCard key={video.id} video={video} />
              ))}
            </div>
          </div>
        )}
      </div>
    </Layout>
  );
}
