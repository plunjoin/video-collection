import React from 'react';
import type { VideoRecord } from '../lib/api';
import BrandIcon from './BrandIcon';

interface Props {
  video: VideoRecord;
  badge?: string;
  rank?: number;
}

export default function VideoCard({ video, badge, rank }: Props) {
  return (
    <article 
      className="video-card" 
      data-track-expose
      data-track-id={video.id} 
      data-track-rank={rank !== undefined ? rank : ''}
    >
      <a 
        className="video-card__link" 
        href={`/anime/${video.id}`}
        data-track="video_click"
        data-track-id={video.id}
        data-track-rank={rank !== undefined ? rank : ''}
      >
        <div className="video-card__cover">
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
          {badge && <span className="video-card__badge">{badge}</span>}
          <span className="video-card__play" aria-hidden="true">
            <BrandIcon name="play" size={32} />
          </span>
        </div>
        <h3>{video.name}</h3>
        <p>{video.remarks || video.type_name || '一起发现好故事'}</p>
        <div className="video-card__meta">
          <span>
            <BrandIcon name="play" size={13} /> {(video.hits ? String(video.hits) : "") || "立即观看"}
          </span>
          <span>
            <BrandIcon name="heart" size={13} /> 追番
          </span>
        </div>
      </a>
      <button 
        className="video-card__pocket" 
        data-pocket-id={video.id} 
        data-pocket-name={video.name} 
        data-pocket-picture={video.picture} 
        aria-pressed="false" 
        aria-label="放进故事口袋" 
        title="放进故事口袋"
      >
        <BrandIcon name="bookmark" size={17} />
      </button>
    </article>
  );
}
