import React, { useState, useEffect } from 'react';
import Layout from '../layouts/Layout';
import HeroBanner from '../components/HeroBanner';
import QuickNav from '../components/QuickNav';
import CurrentlyAiring from '../components/CurrentlyAiring';
import FeaturedRecommend from '../components/FeaturedRecommend';
import ForYou from '../components/ForYou';
import AdSlot from '../components/AdSlot';
import HomePanels from '../components/HomePanels';
import HomeNews from '../components/HomeNews';
import StoryMood from '../components/StoryMood';
import StoryBookmark from '../components/StoryBookmark';
import { getAnimeVideos, getRankings, getNewsList, type VideoRecord, type ContentItem } from '../lib/api';

interface Props {
  animeList?: VideoRecord[];
  rankings?: { top: VideoRecord[] };
  newsItems?: ContentItem[];
}

export default function HomePage(props: Props) {
  const [animeList, setAnimeList] = useState<VideoRecord[]>(props.animeList || []);
  const [rankings, setRankings] = useState<{ top: VideoRecord[] }>(props.rankings || { top: [] });
  const [newsItems, setNewsItems] = useState<ContentItem[]>(props.newsItems || []);

  useEffect(() => {
    if (animeList.length === 0) {
      Promise.all([
        getAnimeVideos(18),
        getRankings(),
        getNewsList({ page: 1, pageSize: 4 }),
      ])
        .then(([animes, ranks, news]) => {
          setAnimeList(animes || []);
          setRankings(ranks || { top: [] });
          setNewsItems(news?.data || []);
        })
        .catch(() => {});
    }
  }, []);

  return (
    <Layout title="bllii — 在更多的故事里，遇见更好的你" activeNav="首页">
      <HeroBanner videos={animeList.slice(0, 5)} />
      {/* 广告位：首页顶部横幅（admin 未配置时自动留空） */}
      <AdSlot slot="banner" />
      <QuickNav />
      <HomeNews items={newsItems} />
      <StoryBookmark />
      {/* 个性化推荐（登录用户） */}
      <ForYou />
      <StoryMood videos={animeList} />
      <CurrentlyAiring animes={animeList.slice(0, 4)} />
      <FeaturedRecommend animes={animeList.slice(4, 12)} />
      <HomePanels latest={animeList} rankings={rankings.top} />
    </Layout>
  );
}
