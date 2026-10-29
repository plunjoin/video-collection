import React from 'react';
import type { VideoRecord } from '../lib/api';

interface Props {
  latest: VideoRecord[];
  rankings: VideoRecord[];
}

export default function HomePanels({ latest = [], rankings = [] }: Props) {
  return (
    <section className="brand-section home-panels">
      <div className="home-panel">
        <div className="section-heading">
          <h2>新番时间表</h2>
          <a href="/latest">更多 →</a>
        </div>
        <div className="panel-subtitle">
          <span data-festival-copy="latest-label">最新更新</span>{' '}
          <span>每一份期待，都值得被回应</span>
        </div>
        {latest.slice(0, 4).map((video) => (
          <a key={video.id} className="schedule-row" href={`/anime/${video.id}`}>
            <span className="schedule-dot"></span>
            <strong>{video.name}</strong>
            <span>{video.remarks || '更新中'}</span>
            <i>追番</i>
          </a>
        ))}
        {!latest.length && <p className="brand-empty">暂无更新</p>}
      </div>

      <div className="home-panel">
        <div className="section-heading">
          <h2>人气排行榜</h2>
          <a href="/rank">完整榜单 →</a>
        </div>
        {rankings.slice(0, 5).map((video, index) => (
          <a key={video.id} className="rank-row" href={`/anime/${video.id}`}>
            <span>{index + 1}</span>
            <strong>{video.name}</strong>
            <small>{video.remarks}</small>
          </a>
        ))}
        {!rankings.length && <p className="brand-empty">暂无排行</p>}
      </div>

      <a className="brand-promo" href="/news">
        <div>
          <p className="brand-eyebrow">STORIES &amp; UPDATES</p>
          <h2>bllii · 资讯速递</h2>
          <p>
            新番情报、制作动态<br />
            以及更多站内精选
          </p>
          <span className="brand-button">去看资讯 →</span>
        </div>
        <img src="/brand/bllii-symbol.svg" alt="" />
      </a>
    </section>
  );
}
