import React, { useState, useEffect, useRef } from 'react';
import BrandIcon from './BrandIcon';
import { getUser, getToken, checkMe, logout } from '../lib/auth';
import { getUnreadCount } from '../lib/notifications';

interface Props {
  activeNav?: string;
}

const navItems = [
  { name: '首页', href: '/' },
  { name: '番剧库', href: '/category' },
  { name: '时间表', href: '/latest' },
  { name: '排行榜', href: '/rank' },
  { name: '追番', href: '/follow' },
  { name: '资讯', href: '/news' },
  { name: '社区', href: '/community' },
];

export default function Navbar({ activeNav = '首页' }: Props) {
  const [user, setUser] = useState<any>(null);
  const [unreadCount, setUnreadCount] = useState(0);
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  const refreshUnread = async () => {
    if (!getToken()) {
      setUnreadCount(0);
      return;
    }
    try {
      const count = await getUnreadCount();
      setUnreadCount(count);
    } catch {
      setUnreadCount(0);
    }
  };

  const updateAuth = () => {
    const u = getUser();
    setUser(u && u.username ? u : null);
  };

  useEffect(() => {
    updateAuth();
    checkMe().then(() => {
      updateAuth();
      void refreshUnread();
    });
    void refreshUnread();

    const handleAuth = () => {
      updateAuth();
      void refreshUnread();
    };
    const handleNotif = () => void refreshUnread();

    window.addEventListener('auth-changed', handleAuth);
    window.addEventListener('notifications-changed', handleNotif);

    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setMenuOpen(false);
      }
    };
    document.addEventListener('click', handleClickOutside);

    return () => {
      window.removeEventListener('auth-changed', handleAuth);
      window.removeEventListener('notifications-changed', handleNotif);
      document.removeEventListener('click', handleClickOutside);
    };
  }, []);

  const handleLogout = async () => {
    await logout();
    updateAuth();
    window.location.reload();
  };

  const roleText = user
    ? ({
        super_admin: '超级管理员',
        admin: '管理员',
        observer: '观察员',
        operator: '运营人员',
      } as Record<string, string>)[user.role] || 'bllii 追番官'
    : '普通用户';

  return (
    <header className="brand-navbar sticky top-0 z-50 w-full bg-white/95 backdrop-blur-md border-b border-slate-100 transition-colors">
      <div className="max-w-[1360px] mx-auto px-4 sm:px-6 h-16 flex items-center justify-between gap-4">
        {/* 左侧 Logo 与导航 */}
        <div className="flex items-center gap-8">
          <a href="/" className="brand-logo" aria-label="bllii 首页">
            <img src="/brand/bllii-horizontal.svg" alt="bllii" width="140" height="54" />
          </a>

          <nav className="hidden lg:flex items-center gap-5">
            {navItems.map((item) => {
              const isActive =
                item.name === activeNav ||
                (activeNav === '番剧' && item.name === '番剧库') ||
                (activeNav === '新番时间表' && item.name === '时间表');
              return (
                <a
                  key={item.name}
                  href={item.href}
                  aria-current={isActive ? 'page' : undefined}
                  className={`text-[13px] font-medium transition-colors ${
                    isActive
                      ? 'text-[#597bea] font-semibold'
                      : 'text-slate-700 hover:text-[#597bea]'
                  }`}
                >
                  {item.name}
                </a>
              );
            })}
          </nav>
        </div>

        {/* 右侧：搜索与用户功能 */}
        <div className="flex items-center gap-3 sm:gap-4">
          <form action="/search" method="GET" className="relative hidden sm:block w-44 xl:w-64">
            <input
              type="text"
              name="q"
              placeholder="搜索番剧、资讯、社区…"
              className="w-full h-9 pl-4 pr-9 rounded-full bg-slate-100/90 text-xs text-slate-700 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:bg-white border border-transparent focus:border-blue-400 transition-all"
            />
            <button
              type="submit"
              aria-label="搜索"
              className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-[#597bea] cursor-pointer"
            >
              <BrandIcon name="search" size={20} className="w-4 h-4 text-blue-500" />
            </button>
          </form>

          <a href="/search" aria-label="搜索内容" className="sm:hidden text-slate-500 p-2">
            <BrandIcon name="search" size={20} />
          </a>

          {/* 消息通知 */}
          <a
            href="/notifications"
            aria-label="消息通知"
            className="w-9 h-9 min-w-[36px] min-h-[36px] aspect-square rounded-full text-slate-500 hover:text-[#597bea] hover:bg-slate-100 flex items-center justify-center transition-colors relative shrink-0"
          >
            <BrandIcon name="bell" size={20} className="w-4.5 h-4.5" />
            {unreadCount > 0 && (
              <span className="absolute -top-1 -right-1 min-w-[17px] h-[17px] px-1 rounded-full bg-rose-500 text-white text-[10px] leading-[17px] text-center">
                {unreadCount > 99 ? '99+' : unreadCount}
              </span>
            )}
          </a>

          {/* 未登录 */}
          {!user && (
            <a
              href="/login"
              className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-blue-50 hover:bg-blue-100 text-[#597bea] text-xs font-semibold transition-all border border-blue-200/60 shadow-sm"
            >
              <BrandIcon name="user" size={16} className="w-3.5 h-3.5" />
              <span>登录 / 注册</span>
            </a>
          )}

          {/* 已登录 */}
          {user && (
            <div ref={menuRef} className="relative group ml-1">
              <button
                type="button"
                onClick={() => setMenuOpen(!menuOpen)}
                className="relative w-9 h-9 min-w-[36px] min-h-[36px] max-w-[36px] max-h-[36px] aspect-square rounded-full flex items-center justify-center focus:outline-none cursor-pointer select-none shrink-0"
                aria-expanded={menuOpen}
              >
                <img
                  src={user.avatar || '/brand/bllii-symbol.svg'}
                  alt="User Avatar"
                  style={{
                    outline: /^#[0-9a-f]{6}$/i.test(user.decorations?.frame || '')
                      ? '3px solid ' + user.decorations!.frame
                      : undefined,
                  }}
                  className="w-9 h-9 min-w-[36px] min-h-[36px] max-w-[36px] max-h-[36px] aspect-square rounded-full object-cover ring-2 ring-[#597bea]/60 group-hover:ring-[#597bea] transition-all shadow-sm shrink-0"
                />
                <span className="absolute bottom-0 right-0 w-2.5 h-2.5 rounded-full bg-emerald-500 ring-2 ring-white"></span>
              </button>

              <div
                className={`nav-dropdown-container absolute right-0 top-full pt-1.5 w-56 transition-all duration-150 z-50 ${
                  menuOpen
                    ? 'opacity-100 pointer-events-auto'
                    : 'opacity-0 pointer-events-none group-hover:opacity-100 group-hover:pointer-events-auto'
                }`}
              >
                <div className="bg-white rounded-2xl shadow-xl shadow-slate-200/80 border border-slate-100/90 py-2 overflow-hidden ring-1 ring-black/5">
                  <div className="px-4 py-2.5 border-b border-slate-100 bg-slate-50/50">
                    <p
                      className="text-xs font-bold text-slate-800 truncate"
                      style={{
                        color: /^#[0-9a-f]{6}$/i.test(user.decorations?.nickname_color || '')
                          ? user.decorations!.nickname_color
                          : undefined,
                      }}
                    >
                      {(user.nickname || user.username) +
                        (user.decorations?.badge ? ' · ' + user.decorations.badge : '')}
                    </p>
                    <p className="text-[10px] text-slate-400 mt-0.5 flex items-center gap-1.5">
                      <span className="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
                      <span>{roleText}</span>
                    </p>
                  </div>

                  <div className="py-1 text-xs text-slate-600">
                    <a href="/points" className="flex items-center gap-2.5 px-4 py-2 hover:bg-blue-50 hover:text-[#597bea]">
                      ✦ 同好成长站
                    </a>
                    <a href="/follow" className="flex items-center gap-2.5 px-4 py-2 hover:bg-blue-50 hover:text-[#597bea] transition-colors">
                      <BrandIcon name="bookmark" size={20} className="w-4 h-4 text-slate-400" />
                      <span>我的追番</span>
                    </a>
                    <a href="/follow?tab=history" className="flex items-center gap-2.5 px-4 py-2 hover:bg-blue-50 hover:text-[#597bea] transition-colors">
                      <BrandIcon name="history" size={20} className="w-4 h-4 text-slate-400" />
                      <span>观看历史</span>
                    </a>
                    <a href="/category" className="flex items-center gap-2.5 px-4 py-2 hover:bg-blue-50 hover:text-[#597bea] transition-colors">
                      <BrandIcon name="library" size={20} className="w-4 h-4 text-slate-400" />
                      <span>发现番剧</span>
                    </a>
                  </div>

                  <div className="pt-1 border-t border-slate-100 px-2 mt-1">
                    <button
                      type="button"
                      onClick={handleLogout}
                      className="w-full flex items-center gap-2 px-3 py-2 text-xs text-rose-500 hover:bg-rose-50 rounded-xl transition-colors cursor-pointer font-medium"
                    >
                      <BrandIcon name="logout" size={20} className="w-4 h-4" />
                      <span>退出登录</span>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
