import React, { useEffect, useRef, useState } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import { resetPassword, sendCode, type ContactChannel } from '../lib/auth';

const inputClass =
  'w-full h-11 pl-4 pr-10 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-800 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-[#597bea] transition-all';

const CHANNELS: Array<{ key: ContactChannel; label: string; placeholder: string; type: string }> = [
  { key: 'email', label: '邮箱', placeholder: '请输入绑定过的邮箱', type: 'email' },
  { key: 'phone', label: '手机号', placeholder: '请输入绑定过的 11 位手机号', type: 'tel' }
];

export default function ResetPasswordPage() {
  const [channel, setChannel] = useState<ContactChannel>('email');
  const [target, setTarget] = useState('');
  const [code, setCode] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [sending, setSending] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [countdown, setCountdown] = useState(0);
  const [done, setDone] = useState(false);
  const [alert, setAlert] = useState<{ text: string; error?: boolean } | null>(null);
  const timer = useRef<number | null>(null);

  const current = CHANNELS.find((item) => item.key === channel) ?? CHANNELS[0];

  useEffect(() => {
    if (countdown <= 0) return;
    timer.current = window.setTimeout(() => setCountdown((n) => n - 1), 1000);
    return () => {
      if (timer.current) window.clearTimeout(timer.current);
    };
  }, [countdown]);

  async function handleSend() {
    const value = target.trim();
    if (!value) {
      setAlert({ text: `请输入${current.label}`, error: true });
      return;
    }
    setSending(true);
    setAlert(null);
    try {
      const res = await sendCode(channel, value, 'reset');
      if (res.code === 1) {
        setCountdown(60);
        setAlert({
          text: res.dev_code
            ? `验证码已发送（联调验证码：${res.dev_code}）`
            : res.msg || '验证码已发送，10 分钟内有效'
        });
        if (res.dev_code) setCode(res.dev_code);
      } else {
        setAlert({ text: res.error || res.msg || '验证码发送失败', error: true });
      }
    } finally {
      setSending(false);
    }
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (submitting) return;
    if (!target.trim()) {
      setAlert({ text: `请输入${current.label}`, error: true });
      return;
    }
    if (!/^\d{6}$/.test(code.trim())) {
      setAlert({ text: '请输入 6 位数字验证码', error: true });
      return;
    }
    if (newPassword.length < 6) {
      setAlert({ text: '新密码长度不能少于 6 位', error: true });
      return;
    }
    if (newPassword !== confirmPassword) {
      setAlert({ text: '两次输入的新密码不一致', error: true });
      return;
    }
    setSubmitting(true);
    setAlert(null);
    try {
      const res = await resetPassword(channel, target.trim(), code.trim(), newPassword);
      if (res.code === 1) {
        setDone(true);
        setAlert({ text: res.msg || '密码已重置，请使用新密码登录' });
        window.setTimeout(() => {
          window.location.href = '/login';
        }, 1500);
      } else {
        setAlert({ text: res.error || res.msg || '密码重置失败', error: true });
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Layout title="找回密码 - AniPocket" activeNav="追番">
      <div className="account-layout">
        <aside className="account-story">
          <img src="/brand/bllii-symbol.svg" alt="" />
          <h1>
            忘了密码也没关系，
            <br />
            我们帮你找回来。
          </h1>
          <p>RESET YOUR PASSWORD</p>
        </aside>

        <div className="account-card relative overflow-hidden">
          <div className="text-center mb-6">
            <a href="/" className="inline-flex mb-3">
              <img src="/brand/bllii-horizontal.svg" alt="bllii" width="170" height="66" />
            </a>
            <p className="text-xs text-slate-400">通过绑定的邮箱或手机号重置密码</p>
          </div>

          <div className="flex items-center bg-slate-100/80 p-1 rounded-2xl mb-6">
            {CHANNELS.map((item) => (
              <button
                key={item.key}
                type="button"
                onClick={() => {
                  setChannel(item.key);
                  setAlert(null);
                  setCode('');
                }}
                className={`flex-1 py-2 text-xs font-bold rounded-xl transition-all cursor-pointer ${
                  channel === item.key ? 'bg-white text-[#597bea] shadow-sm' : 'text-slate-500'
                }`}
              >
                {item.label}找回
              </button>
            ))}
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

          {done ? (
            <div className="text-center">
              <p className="mb-4 text-xs text-slate-500">正在跳转到登录页…</p>
              <a
                href="/login"
                className="inline-flex h-11 items-center justify-center rounded-xl px-6 text-xs font-semibold text-white shadow-md"
                style={{ background: 'var(--brand-gradient)' }}
              >
                立即登录
              </a>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1.5">{current.label}</label>
                <div className="relative">
                  <input
                    type={current.type}
                    value={target}
                    onChange={(event) => setTarget(event.target.value)}
                    placeholder={current.placeholder}
                    className={inputClass}
                  />
                  <div className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
                    <BrandIcon name="user" size={16} />
                  </div>
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1.5">验证码</label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    inputMode="numeric"
                    value={code}
                    onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
                    placeholder="6 位验证码"
                    className={`${inputClass} flex-1`}
                  />
                  <button
                    type="button"
                    disabled={sending || countdown > 0}
                    onClick={() => void handleSend()}
                    className="h-11 shrink-0 rounded-xl border border-slate-200 px-3 text-[11px] font-semibold text-slate-600 transition-colors hover:border-[#597bea] hover:text-[#597bea] disabled:opacity-50"
                  >
                    {countdown > 0 ? `${countdown}s` : sending ? '发送中…' : '获取验证码'}
                  </button>
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1.5">新密码</label>
                <div className="relative">
                  <input
                    type="password"
                    value={newPassword}
                    onChange={(event) => setNewPassword(event.target.value)}
                    placeholder="至少 6 位"
                    autoComplete="new-password"
                    className={inputClass}
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1.5">确认新密码</label>
                <div className="relative">
                  <input
                    type="password"
                    value={confirmPassword}
                    onChange={(event) => setConfirmPassword(event.target.value)}
                    placeholder="再次输入新密码"
                    autoComplete="new-password"
                    className={inputClass}
                  />
                </div>
              </div>

              <button
                type="submit"
                disabled={submitting}
                className="w-full h-11 rounded-xl text-white font-semibold text-xs transition-all shadow-md cursor-pointer disabled:opacity-60"
                style={{ background: 'var(--brand-gradient)' }}
              >
                {submitting ? '提交中…' : '重置密码'}
              </button>

              <p className="text-center text-[11px] text-slate-400">
                重置成功后所有设备都会被下线，需要用新密码重新登录。
              </p>
              <p className="text-center text-[11px] text-slate-400">
                还没绑定邮箱或手机？<a href="/login" className="text-[#597bea]">先登录后在账号设置里绑定</a>
              </p>
            </form>
          )}
        </div>
      </div>
    </Layout>
  );
}
