import React, { useState } from 'react';
import type { VideoRecord } from '../lib/api';
import VideoCard from './VideoCard';
import AdSlot from './AdSlot';

interface Props {
  animes?: VideoRecord[];
}

const genres = ['全部', '热血', '恋爱', '奇幻', '日常', '治愈'];

export default function FeaturedRecommend({ animes = [] }: Props) {
  const [selectedGenre, setSelectedGenre] = useState('全部');

  const filtered = animes.filter((video) => {
    if (selectedGenre === '全部') return true;
    return video.tags?.includes(selectedGenre);
  });

  return (
    <section id="recommend" className="brand-section" data-recommend>
      <div className="section-heading section-heading--wrap">
        <h2>为你推荐</h2>
        <div className="brand-chips" role="group" aria-label="推荐题材">
          {genres.map((genre) => (
            <button
              key={genre}
              type="button"
              onClick={() => setSelectedGenre(genre)}
              aria-pressed={selectedGenre === genre}
            >
              {genre}
            </button>
          ))}
        </div>
        <a href="/category">更多 →</a>
      </div>
      <div className="video-grid">
        {filtered.map((video, i) => (
          <React.Fragment key={video.id}>
            {i === 4 && <AdSlot slot="home_recommend" inline limit={2} dataTags="广告" />}
            <div>
              <VideoCard video={video} />
            </div>
          </React.Fragment>
        ))}
      </div>
      {filtered.length === 0 && (
        <p className="brand-empty">暂时没有这个题材的推荐，去番剧库发现更多故事吧。</p>
      )}
    </section>
  );
}
