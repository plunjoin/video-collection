import React, { useState, useEffect } from 'react';
import BrandIcon from './BrandIcon';
import type { VideoRecord } from '../lib/api';

interface Props {
  videos: VideoRecord[];
}

const moods = [
  { name: '放松一下', icon: 'smile', tags: ['日常', '治愈', '搞笑'], tone: 'mint' },
  { name: '想要心动', icon: 'heart', tags: ['恋爱', '青春'], tone: 'pink' },
  { name: '去冒险吧', icon: 'compass', tags: ['冒险', '奇幻', '热血'], tone: 'blue' },
  { name: '随缘遇见', icon: 'sparkles', tags: [], tone: 'purple' },
];

export default function StoryMood({ videos }: Props) {
  const [selectedMood, setSelectedMood] = useState(0);
  const [chosenVideo, setChosenVideo] = useState<VideoRecord | null>(null);

  const choose = (moodIndex: number) => {
    const targetMood = moods[moodIndex];
    const tags = targetMood.tags;
    const matches = videos.filter((v) => !tags.length || v.tags?.some((t) => tags.includes(t)));
    const choices = matches.length > 0 ? matches : videos;
    if (choices.length > 0) {
      const idx = Math.floor(Math.random() * choices.length);
      setChosenVideo(choices[idx]);
    }
  };

  useEffect(() => {
    let saved = 0;
    try {
      const s = Number(localStorage.getItem('bllii_story_mood'));
      if (Number.isInteger(s) && s >= 0 && s < moods.length) saved = s;
    } catch {}
    setSelectedMood(saved);
    choose(saved);
  }, [videos]);

  const onSelect = (i: number) => {
    setSelectedMood(i);
    choose(i);
    try {
      localStorage.setItem('bllii_story_mood', String(i));
    } catch {}
  };

  const currentTone = moods[selectedMood]?.tone || 'mint';

  return (
    <section className="brand-section story-mood" data-tone={currentTone}>
      <div className="mood-toolbar">
        <div className="mood-heading">
          <span className="tiny-label">STORY RADIO</span>
          <h2>今天，是什么心情？</h2>
        </div>
        <div className="mood-options" role="group" aria-label="选番心情">
          {moods.map((mood, i) => (
            <button
              key={mood.name}
              type="button"
              className={`mood-option mood-option--${mood.tone}`}
              aria-pressed={i === selectedMood}
              onClick={() => onSelect(i)}
            >
              <BrandIcon name={mood.icon} />
              <span>{mood.name}</span>
            </button>
          ))}
        </div>
        <button 
          type="button"
          className="icon-command" 
          onClick={() => choose(selectedMood)} 
          title="再遇见一部" 
          aria-label="再遇见一部"
        >
          <BrandIcon name="shuffle" />
        </button>
      </div>

      <div className="mood-result" aria-live="polite" aria-atomic="true">
        {chosenVideo && (
          <img
            src={chosenVideo.picture || '/brand/bllii-app-light.svg'}
            alt=""
            onError={(e) => {
              const target = e.currentTarget;
              target.onerror = null;
              target.src = '/brand/bllii-app-light.svg';
            }}
          />
        )}
        <div>
          <span className="tiny-label">给今天的一份小小推荐</span>
          <h3>{chosenVideo ? chosenVideo.name : '这份心情，去番剧库找找吧'}</h3>
          <p>
            {chosenVideo
              ? [chosenVideo.remarks, ...(chosenVideo.tags || []).slice(0, 3)].filter(Boolean).join(' · ')
              : '从喜欢的心情开始'}
          </p>
        </div>
        <a href={chosenVideo ? `/anime/${chosenVideo.id}` : '/category'} className="mood-result__link">
          <span>{chosenVideo ? '就看这部' : '发现番剧'}</span>
          <BrandIcon name="arrow-right" />
        </a>
      </div>
    </section>
  );
}
