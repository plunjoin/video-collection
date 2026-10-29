import React, { useState } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import { login, register } from '../lib/auth';

export default function LoginPage() {
  const [tab, setTab] = useState<'login' | 'register'>('login');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [nickname, setNickname] = useState('');
  const [loading, setLoading] = useState(false);
  const [alert, setAlert] = useState<{ text: string; error?: boolean } | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setAlert(null);

    try {
      if (tab === 'login') {
        const res = await login(username, password);
        if (res.code === 1) {
          setAlert({ text: '登录成功，正在跳转...' });
          setTimeout(() => {
            window.location.href = '/';
          }, 600);
        } else {
          setAlert({ text: res.msg || '登录失败，请检查账号密码', error: true });
        }
      } else {
        const res = await register(username, password, nickname || username);
        if (res.code === 1) {
          setAlert({ text: '注册成功，已自动登录！' });
          setTimeout(() => {
            window.location.href = '/';
          }, 600);
        } else {
          setAlert({ text: res.msg || '注册失败', error: true });
        }
      }
    } catch (err: any) {
      setAlert({ text: err.message || '网络请求错误', error: true });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Layout title="用户登录 / 注册 - bllii" activeNav="追番">
      <div className="account-layout">
        <aside className="account-story">
          <img src="/brand/bllii-symbol.svg" alt="" />
          <h1>更多的故事里，<br />遇见更好的你。</h1>
          <p>MORE STORIES, TOGETHER</p>
        </aside>

        <div className="account-card relative overflow-hidden">
          <div className="text-center mb-6">
            <a href="/" className="inline-flex mb-3">
              <img src="/brand/bllii-horizontal.svg" alt="bllii" width="170" height="66" />
            </a>
            <p className="text-xs text-slate-400">在更多的故事里，遇见更好的你 · 账户中心</p>
          </div>

          <div className="flex items-center bg-slate-100/80 p-1 rounded-2xl mb-6">
            <button
              type="button"
              onClick={() => { setTab('login'); setAlert(null); }}
              className={`flex-1 py-2 text-xs font-bold rounded-xl transition-all cursor-pointer ${
                tab === 'login' ? 'bg-white text-[#597bea] shadow-sm' : 'text-slate-500'
              }`}
            >
              账号登录
            </button>
            <button
              type="button"
              onClick={() => { setTab('register'); setAlert(null); }}
              className={`flex-1 py-2 text-xs font-semibold rounded-xl transition-all cursor-pointer ${
                tab === 'register' ? 'bg-white text-[#597bea] shadow-sm' : 'text-slate-500'
              }`}
            >
              免费注册
            </button>
          </div>

          {alert && (
            <div
              className={`mb-4 p-3 rounded-xl text-xs font-medium border ${
                alert.error
                  ? 'bg-rose-50 border-rose-200 text-rose-600'
                  : 'bg-emerald-50 border-emerald-200 text-emerald-600'
              }`}
            >
              {alert.text}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-xs font-semibold text-slate-600 mb-1.5">用户名 / 账号</label>
              <div className="relative">
                <input
                  type="text"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="请输入用户名"
                  required
                  className="w-full h-11 pl-4 pr-10 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-800 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-[#597bea] transition-all"
                />
                <div className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
                  <BrandIcon name="user" size={16} />
                </div>
              </div>
            </div>

            {tab === 'register' && (
              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1.5">昵称（选填）</label>
                <div className="relative">
                  <input
                    type="text"
                    value={nickname}
                    onChange={(e) => setNickname(e.target.value)}
                    placeholder="给自己起一个喜欢的昵称"
                    className="w-full h-11 pl-4 pr-10 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-800 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-[#597bea] transition-all"
                  />
                </div>
              </div>
            )}

            <div>
              <label className="block text-xs font-semibold text-slate-600 mb-1.5">密码</label>
              <div className="relative">
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="请输入密码"
                  required
                  className="w-full h-11 pl-4 pr-10 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-800 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-[#597bea] transition-all"
                />
              </div>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full h-11 rounded-xl text-white font-semibold text-xs transition-all shadow-md cursor-pointer disabled:opacity-60"
              style={{ background: 'var(--brand-gradient)' }}
            >
              {loading ? '提交中...' : tab === 'login' ? '立即登录' : '立即注册'}
            </button>
          </form>
        </div>
      </div>
    </Layout>
  );
}
