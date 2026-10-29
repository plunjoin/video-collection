import React from 'react';
import type { VideoRecord } from '../lib/api';
import VideoCard from './VideoCard';

interface Props {
  animes: VideoRecord[];
}

export default function CurrentlyAiring({ animes = [] }: Props) {
  return (
    <section id="hot" className="brand-section">
      <div className="section-heading">
        <h2>正在热播 <span>›</span></h2>
        <a href="/category">查看更多 →</a>
      </div>
      <div className="video-grid">
        {animes.slice(0, 4).map((video, i) => (
          <VideoCard key={video.id} video={video} badge={i === 0 ? '热播' : undefined} />
        ))}
      </div>
      {animes.length === 0 && <p className="brand-empty">故事正在路上，稍后再来看看吧。</p>}
    </section>
  );
}
