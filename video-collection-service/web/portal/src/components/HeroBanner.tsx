import React, { useState, useEffect, useRef } from 'react';
import type { VideoRecord } from '../lib/api';
import BrandIcon from './BrandIcon';

interface Props {
  featuredVideo?: VideoRecord;
  videos?: VideoRecord[];
}

const AUTOPLAY_INTERVAL = 6000;

export default function HeroBanner({ featuredVideo, videos = [] }: Props) {
  const slides = videos.length ? videos.slice(0, 5) : featuredVideo ? [featuredVideo] : [];
  const [current, setCurrent] = useState(0);
  const [paused, setPaused] = useState(false);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const touchXRef = useRef<number | null>(null);

  const prevSlide = () => {
    if (slides.length <= 1) return;
    setCurrent((prev) => (prev - 1 + slides.length) % slides.length);
  };

  const nextSlide = () => {
    if (slides.length <= 1) return;
    setCurrent((prev) => (prev + 1) % slides.length);
  };

  // 自动轮换：悬停/聚焦暂停，页签不可见暂停，系统减少动效时不自动播
  useEffect(() => {
    if (slides.length <= 1 || paused) return;
    if (typeof window === 'undefined') return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    timerRef.current = setInterval(() => {
      if (document.hidden) return;
      setCurrent((prev) => (prev + 1) % slides.length);
    }, AUTOPLAY_INTERVAL);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [slides.length, paused]);

  const onTouchStart = (e: React.TouchEvent) => {
    touchXRef.current = e.touches[0]?.clientX ?? null;
  };

  const onTouchEnd = (e: React.TouchEvent) => {
    if (touchXRef.current === null || slides.length <= 1) return;
    const dx = (e.changedTouches[0]?.clientX ?? touchXRef.current) - touchXRef.current;
    if (dx > 48) prevSlide();
    if (dx < -48) nextSlide();
    touchXRef.current = null;
  };

  const renderSlides = slides.length ? slides : [null];

  return (
    <section className="brand-section hero-section">
      <div data-hero>
        <div
          className="brand-hero"
          onMouseEnter={() => setPaused(true)}
          onMouseLeave={() => setPaused(false)}
          onFocusCapture={() => setPaused(true)}
          onBlurCapture={() => setPaused(false)}
          onTouchStart={onTouchStart}
          onTouchEnd={onTouchEnd}
        >
          {renderSlides.map((video, i) => (
            <div
              key={video ? video.id : 'default'}
              className="brand-hero__slide"
              data-slide
              hidden={i !== current}
            >
              <img
                className="brand-hero__image"
                src={video?.picture || '/assets/hero_banner.jpg'}
                alt={video?.name || 'AniPocket 故事口袋'}
                loading={i === 0 ? 'eager' : 'lazy'}
                onError={(e) => {
                  const target = e.currentTarget;
                  target.onerror = null;
                  target.src = '/assets/hero_banner.jpg';
                }}
              />
              <div className="brand-hero__shade"></div>
              <div className="brand-hero__copy">
                <p className="brand-eyebrow">
                  <span data-festival-copy="hero-eyebrow">AniPocket 故事口袋 / 今日精选</span>{' '}
                  <span className="hero-story-number">{String(i + 1).padStart(2, '0')}</span>
                </p>
                <h1>{video?.name || 'AniPocket 故事口袋 · 故事与资讯'}</h1>
                <p className="brand-hero__title">
                  {video
                    ? [video.year, video.remarks, ...(video.tags || []).slice(0, 2)].filter(Boolean).join(' · ')
                    : '在更多的故事里，遇见更好的你'}
                </p>
                <a className="brand-button" href={video ? `/play/${video.id}` : '/category'}>
                  <BrandIcon name="play" />
                  {video ? '立即观看' : '去发现'}
                </a>
              </div>
              <span className="brand-hero__note" aria-hidden="true">
                MORE STORIES,<br />TOGETHER.
              </span>
            </div>
          ))}

          {slides.length > 1 && (
            <>
              <button
                type="button"
                className="hero-arrow hero-arrow--prev"
                onClick={prevSlide}
                aria-label="上一张"
                title="上一张"
              >
                <BrandIcon name="arrow-left" />
              </button>
              <button
                type="button"
                className="hero-arrow hero-arrow--next"
                onClick={nextSlide}
                aria-label="下一张"
                title="下一张"
              >
                <BrandIcon name="arrow-right" />
              </button>
            </>
          )}
        </div>

        {slides.length > 1 && (
          <div className="story-reel" aria-label="今日放映列表">
            {slides.map((video, i) => (
              <button
                key={video.id}
                onClick={() => setCurrent(i)}
                aria-pressed={i === current}
              >
                <span className="story-reel__number">{String(i + 1).padStart(2, '0')}</span>
                <img
                  src={video.picture || '/assets/hero_banner.jpg'}
                  alt=""
                  onError={(e) => {
                    const target = e.currentTarget;
                    target.onerror = null;
                    target.src = '/assets/hero_banner.jpg';
                  }}
                />
                <span>{video.name}</span>
              </button>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
