import React, { useEffect, useContext } from 'react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import SecurityGuard from '../components/SecurityGuard';
import PageIntro from '../components/PageIntro';
import BrandIcon from '../components/BrandIcon';
import StoryPocket from '../components/StoryPocket';
import ConfirmDialog from '../components/ConfirmDialog';
import { applyFestival } from '../lib/festival';
import { RouteContext } from '../App';

interface Props {
  title?: string;
  activeNav?: string;
  description?: string;
  children?: React.ReactNode;
}

const pageIntros: Record<string, { title: string; description: string; eyebrow: string }> = {
  category: { title: '发现你的下一份喜欢', description: '从心动的题材开始，遇见属于你的好故事。', eyebrow: 'FIND YOUR NEXT STORY' },
  search: { title: '寻找让你心动的故事', description: '记得一个名字，就能再次相遇。', eyebrow: 'A LITTLE SEARCH, A NEW WORLD' },
  rank: { title: '大家的热爱，都在这里', description: '人气与口碑，一起发现值得追的好番。', eyebrow: 'STORIES WE ALL LOVE' },
  latest: { title: '今天，也有新的期待', description: '收好这份更新清单，不错过喜欢的每一集。', eyebrow: 'A NEW DAY, A NEW EPISODE' },
  follow: { title: '我的故事收藏夹', description: '每一次心动，每一段陪伴，都替你好好珍藏。', eyebrow: 'YOUR LITTLE HAPPY PLACE' },
  news: { title: '故事之外，也很精彩', description: '新番情报、制作动态与编辑精选。', eyebrow: 'MORE BEHIND THE STORIES' },
  community: { title: '和同好，一起热爱', description: '分享喜欢的瞬间，让故事成为相遇的开始。', eyebrow: 'FOR FANS, TOGETHER' },
  points: { title: '让每一份热爱，都有回响', description: '收藏故事、遇见同好，把小小的日常变成值得珍藏的光。', eyebrow: 'YOUR STORY, YOUR LITTLE SPARK' },
};

export default function Layout({
  title = 'bllii - 在更多的故事里，遇见更好的你',
  activeNav = '首页',
  description = 'bllii 动漫番剧在线播放与聚合平台',
  children
}: Props) {
  useEffect(() => {
    try {
      applyFestival();
    } catch {}

    if ('serviceWorker' in navigator) {
      window.addEventListener('load', function () {
        navigator.serviceWorker.register('/sw.js').catch(function () {});
      });
    }
  }, []);

  const routeCtx = useContext(RouteContext);
  const rawPath = routeCtx?.url || (typeof window !== 'undefined' ? window.location.pathname : '/');
  const pathname = rawPath.split('?')[0];
  const page = pathname.split('/').filter(Boolean)[0] || 'home';
  const intro = pageIntros[page];

  return (
    <div className="bllii-site min-h-screen bg-slate-50 text-slate-800 flex flex-col antialiased selection:bg-primary-500 selection:text-white">
      <SecurityGuard />
      <div className="brand-shell">
        <Navbar activeNav={activeNav} />
        <main className="bllii-page flex-1 pb-16" data-page={page}>
          <div className="festival-ribbon" data-festival-ribbon hidden></div>
          {intro && <PageIntro {...intro} />}
          {children}
        </main>
        <Footer />
      </div>

      <nav className="mobile-nav" aria-label="移动端导航">
        <a href="/" aria-current={activeNav === '首页' ? 'page' : undefined}>
          <BrandIcon name="home" size={24} />
          首页
        </a>
        <a href="/category" aria-current={['番剧', '番剧库'].includes(activeNav) ? 'page' : undefined}>
          <BrandIcon name="compass" size={24} />
          发现
        </a>
        <a href="/rank" className="mobile-nav__brand" aria-label="人气排行榜">
          <img src="/brand/bllii-symbol.svg" alt="" />
        </a>
        <a href="/latest" aria-current={activeNav === '新番时间表' ? 'page' : undefined}>
          <BrandIcon name="calendar" size={24} />
          更新
        </a>
        <a href="/follow" aria-current={activeNav === '追番' ? 'page' : undefined}>
          <BrandIcon name="bookmark" size={24} />
          我的
        </a>
      </nav>

      <StoryPocket />
      <ConfirmDialog />
    </div>
  );
}
