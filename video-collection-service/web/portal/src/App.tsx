import React from 'react';
import HomePage from './pages/HomePage';
import CategoryPage from './pages/CategoryPage';
import PlayPage from './pages/PlayPage';
import AnimeDetailPage from './pages/AnimeDetailPage';
import RankPage from './pages/RankPage';
import LatestPage from './pages/LatestPage';
import FollowPage from './pages/FollowPage';
import SearchPage from './pages/SearchPage';
import LoginPage from './pages/LoginPage';
import NewsPage from './pages/NewsPage';
import NewsDetailPage from './pages/NewsDetailPage';
import CommunityPage from './pages/CommunityPage';
import CommunityDetailPage from './pages/CommunityDetailPage';
import NotificationsPage from './pages/NotificationsPage';
import PointsPage from './pages/PointsPage';

export const RouteContext = React.createContext<{ url: string }>({ url: '/' });

interface AppProps {
  url?: string;
  [key: string]: any;
}

export default function App({ url = '/', ...props }: AppProps) {
  // Normalize path and query
  const [rawPath, rawSearch = ''] = url.split('?');
  const path = (rawPath.replace(/\/+$/, '') || '/');

  // Extract query parameters defensively
  const getQueryParam = (key: string): string => {
    if (rawSearch) {
      const p = new URLSearchParams(rawSearch);
      const val = p.get(key);
      if (val) return val;
    }
    if (typeof window !== 'undefined' && window.location && window.location.search) {
      const p = new URLSearchParams(window.location.search);
      const val = p.get(key);
      if (val) return val;
    }
    return '';
  };

  const renderContent = () => {
    if (path === '/' || path === '') {
      return <HomePage {...props} />;
    }

    if (path === '/category') {
      return <CategoryPage {...props} />;
    }

    // 播放页：/play/:id, /play?id=:id, /play
    if (path.startsWith('/play/')) {
      const id = path.replace('/play/', '').replace(/\/.*$/, '');
      return <PlayPage id={id || props.id || '317'} {...props} />;
    }
    if (path === '/play') {
      const id = getQueryParam('id') || props.id || '317';
      return <PlayPage id={id} {...props} />;
    }

    // 详情页：/anime/:id, /anime?id=:id, /detail/:id, /detail?id=:id
    if (path.startsWith('/anime/')) {
      const id = path.replace('/anime/', '').replace(/\/.*$/, '');
      return <AnimeDetailPage id={id || props.id || '317'} {...props} />;
    }
    if (path === '/anime') {
      const id = getQueryParam('id') || props.id;
      if (id) {
        return <AnimeDetailPage id={id} {...props} />;
      }
      return <CategoryPage {...props} />;
    }
    if (path.startsWith('/detail/')) {
      const id = path.replace('/detail/', '').replace(/\/.*$/, '');
      return <AnimeDetailPage id={id || props.id || '317'} {...props} />;
    }
    if (path === '/detail') {
      const id = getQueryParam('id') || props.id;
      if (id) {
        return <AnimeDetailPage id={id} {...props} />;
      }
      return <CategoryPage {...props} />;
    }

    if (path === '/rank') {
      return <RankPage {...props} />;
    }

    if (path === '/latest' || path === '/timeline') {
      return <LatestPage {...props} />;
    }

    if (path === '/follow') {
      return <FollowPage {...props} />;
    }

    if (path === '/search') {
      return <SearchPage {...props} />;
    }

    if (path === '/login') {
      return <LoginPage {...props} />;
    }

    if (path === '/news') {
      return <NewsPage {...props} />;
    }
    if (path.startsWith('/news/')) {
      const id = path.replace('/news/', '').replace(/\/.*$/, '');
      return <NewsDetailPage id={parseInt(id, 10) || 0} {...props} />;
    }

    if (path === '/community') {
      return <CommunityPage {...props} />;
    }
    if (path.startsWith('/community/')) {
      const id = path.replace('/community/', '').replace(/\/.*$/, '');
      return <CommunityDetailPage id={parseInt(id, 10) || 0} {...props} />;
    }

    if (path === '/notifications') {
      return <NotificationsPage {...props} />;
    }

    if (path === '/points') {
      return <PointsPage {...props} />;
    }

    // 404 Fallback
    return (
      <div className="min-h-screen flex items-center justify-center flex-col gap-4 bg-slate-50">
        <img src="/brand/bllii-symbol.svg" width={64} height={64} alt="" />
        <h1 className="text-xl font-bold text-slate-800">404 - 页面未找到</h1>
        <p className="text-sm text-slate-500">故事可能已经启程去往别处。</p>
        <a href="/" className="px-5 py-2.5 bg-[#597bea] text-white font-semibold rounded-xl text-xs shadow-md">
          返回首页
        </a>
      </div>
    );
  };

  return (
    <RouteContext.Provider value={{ url }}>
      {renderContent()}
    </RouteContext.Provider>
  );
}
