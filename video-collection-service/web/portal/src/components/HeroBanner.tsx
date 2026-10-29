import React, { useState } from 'react';
import type { VideoRecord } from '../lib/api';
import BrandIcon from './BrandIcon';

interface Props {
  featuredVideo?: VideoRecord;
  videos?: VideoRecord[];
}

export default function HeroBanner({ featuredVideo, videos = [] }: Props) {
  const slides = videos.length ? videos.slice(0, 5) : featuredVideo ? [featuredVideo] : [];
  const [current, setCurrent] = useState(0);

  const prevSlide = () => {
    if (slides.length <= 1) return;
    setCurrent((prev) => (prev - 1 + slides.length) % slides.length);
  };

  const nextSlide = () => {
    if (slides.length <= 1) return;
    setCurrent((prev) => (prev + 1) % slides.length);
  };

  const renderSlides = slides.length ? slides : [null];

  return (
    <section className="brand-section hero-section">
      <div data-hero>
        <div className="brand-hero">
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
                alt={video?.name || 'bllii'} 
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
                  <span data-festival-copy="hero-eyebrow">bllii / 今日精选</span>{' '}
                  <span className="hero-story-number">{String(i + 1).padStart(2, '0')}</span>
                </p>
                <h1>{video?.name || 'bllii · 故事与资讯'}</h1>
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
