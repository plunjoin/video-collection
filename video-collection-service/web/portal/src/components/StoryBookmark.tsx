import React, { useState, useEffect } from 'react';
import BrandIcon from './BrandIcon';
import { readLatestBookmark } from '../lib/story-bookmark';

export default function StoryBookmark() {
  const [bookmark, setBookmark] = useState<any>(null);
  const [hidden, setHidden] = useState(false);

  useEffect(() => {
    try {
      const bm = readLatestBookmark();
      if (bm) setBookmark(bm);
    } catch {}
  }, []);

  if (!bookmark || hidden) return null;

  const minutes = Math.floor(bookmark.currentTime / 60);
  const seconds = Math.floor(bookmark.currentTime % 60).toString().padStart(2, '0');
  const metaText = `${bookmark.episodeName} · 上次看到 ${minutes}:${seconds}`;
  const url = `/play/${bookmark.videoId}?ep=${bookmark.episodeIndex}&route=${bookmark.routeIndex}`;
  const progressVal = Math.min(100, Math.max(0, bookmark.duration ? (bookmark.currentTime / bookmark.duration) * 100 : 0));

  return (
    <section className="brand-section story-bookmark" aria-label="继续观看">
      <BrandIcon name="bookmark" size={24} />
      <div className="story-bookmark__copy">
        <span className="tiny-label">你的故事书签</span>
        <a href={url}>
          <strong>{bookmark.videoName}</strong>
          <span>{metaText}</span>
        </a>
      </div>
      <progress max="100" value={progressVal} aria-label="观看进度"></progress>
      <a href={url} className="resume-command" title="继续观看" aria-label="继续观看">
        <BrandIcon name="play" />
      </a>
      <button 
        type="button"
        onClick={() => setHidden(true)} 
        className="icon-command" 
        title="收起书签" 
        aria-label="收起书签"
      >
        <BrandIcon name="close" size={16} />
      </button>
    </section>
  );
}
