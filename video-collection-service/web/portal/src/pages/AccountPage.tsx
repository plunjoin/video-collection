import React, { useEffect, useMemo, useRef, useState } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import {
  bindContact,
  changePassword,
  checkMe,
  clearSession,
  deleteAccount,
  deleteAvatar,
  getContact,
  getSessions,
  listAvatars,
  revokeSession,
  sendCode,
  unbindContact,
  updateProfile,
  uploadAvatar,
  useAvatar,
  type AvatarHistoryItem,
  type ContactChannel,
  type LoginSession,
  type User,
  type UserContact
} from '../lib/auth';

type TabKey = 'profile' | 'security' | 'devices';

const TABS: Array<{ key: TabKey; label: string }> = [
  { key: 'profile', label: '个人资料' },
  { key: 'security', label: '账号安全' },
  { key: 'devices', label: '登录设备' }
];

interface Notice {
  text: string;
  error?: boolean;
}

const inputClass =
  'w-full h-11 px-4 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-800 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-[#597bea] transition-all';
const labelClass = 'block text-xs font-semibold text-slate-600 mb-1.5';
const primaryButtonClass =
  'h-11 px-6 rounded-xl text-white font-semibold text-xs transition-all shadow-md cursor-pointer disabled:opacity-60';
const ghostButtonClass =
  'h-9 rounded-xl border border-slate-200 px-3 text-[11px] font-semibold text-slate-600 transition-colors hover:border-[#597bea] hover:text-[#597bea] disabled:opacity-50';

function describeAgent(userAgent: string): string {
  if (!userAgent) return '未知设备';
  const browser = /Edg\//.test(userAgent)
    ? 'Edge'
    : /Chrome\//.test(userAgent)
      ? 'Chrome'
      : /Firefox\//.test(userAgent)
        ? 'Firefox'
        : /Safari\//.test(userAgent)
          ? 'Safari'
          : '浏览器';
  const os = /Windows/.test(userAgent)
    ? 'Windows'
    : /Android/.test(userAgent)
      ? 'Android'
      : /iPhone|iPad|iPod/.test(userAgent)
        ? 'iOS'
        : /Mac OS X/.test(userAgent)
          ? 'macOS'
          : /Linux/.test(userAgent)
            ? 'Linux'
            : '';
  return os ? `${browser} · ${os}` : browser;
}

function formatTime(value: string): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString('zh-CN', { hour12: false });
}

function NoticeLine({ notice }: { notice: Notice | null }) {
  if (!notice) return null;
  return (
    <p
      className={`rounded-xl border p-3 text-xs ${
        notice.error
          ? 'border-rose-200 bg-rose-50 text-rose-600'
          : 'border-emerald-200 bg-emerald-50 text-emerald-600'
      }`}
    >
      {notice.text}
    </p>
  );
}

/** 邮箱 / 手机绑定卡片：未绑定时展示绑定表单，已绑定时展示值 + 解绑入口。 */
function ContactCard({
  channel,
  label,
  placeholder,
  contact,
  onChanged
}: {
  channel: ContactChannel;
  label: string;
  placeholder: string;
  contact: UserContact | null;
  onChanged: (next: UserContact) => void;
}) {
  const bound = channel === 'email' ? contact?.email || '' : contact?.phone || '';
  const verified = channel === 'email' ? contact?.email_verified : contact?.phone_verified;

  const [target, setTarget] = useState('');
  const [code, setCode] = useState('');
  const [notice, setNotice] = useState<Notice | null>(null);
  const [sending, setSending] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [countdown, setCountdown] = useState(0);
  const [unbinding, setUnbinding] = useState(false);
  const [password, setPassword] = useState('');
  const timer = useRef<number | null>(null);

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
      setNotice({ text: `请输入${label}`, error: true });
      return;
    }
    setSending(true);
    setNotice(null);
    try {
      const res = await sendCode(channel, value, 'bind');
      if (res.code === 1) {
        setCountdown(60);
        setNotice({
          text: res.dev_code ? `验证码已发送（联调验证码：${res.dev_code}）` : '验证码已发送，10 分钟内有效'
        });
        if (res.dev_code) setCode(res.dev_code);
      } else {
        setNotice({ text: res.error || res.msg || '验证码发送失败', error: true });
      }
    } finally {
      setSending(false);
    }
  }

  async function handleBind(event: React.FormEvent) {
    event.preventDefault();
    if (submitting) return;
    if (!target.trim()) {
      setNotice({ text: `请输入${label}`, error: true });
      return;
    }
    if (!/^\d{6}$/.test(code.trim())) {
      setNotice({ text: '请输入 6 位数字验证码', error: true });
      return;
    }
    setSubmitting(true);
    setNotice(null);
    try {
      const res = await bindContact(channel, target.trim(), code.trim());
      if (res.code === 1) {
        const next = await getContact();
        if (next) onChanged(next);
        setTarget('');
        setCode('');
        setNotice({ text: `${label}绑定成功` });
      } else {
        setNotice({ text: res.error || res.msg || '绑定失败', error: true });
      }
    } finally {
      setSubmitting(false);
    }
  }

  async function handleUnbind() {
    if (!password) {
      setNotice({ text: '请输入当前密码以确认解绑', error: true });
      return;
    }
    setSubmitting(true);
    setNotice(null);
    try {
      const res = await unbindContact(channel, password);
      if (res.code === 1) {
        const next = await getContact();
        if (next) onChanged(next);
        setPassword('');
        setUnbinding(false);
        setNotice({ text: `${label}已解绑` });
      } else {
        setNotice({ text: res.error || res.msg || '解绑失败', error: true });
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="rounded-xl border border-slate-100 bg-slate-50/60 p-4">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <h3 className="text-xs font-bold text-slate-800">{label}</h3>
          {bound ? (
            <span
              className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                verified ? 'bg-emerald-50 text-emerald-600' : 'bg-amber-50 text-amber-600'
              }`}
            >
              {verified ? '已验证' : '未验证'}
            </span>
          ) : (
            <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-semibold text-slate-400">
              未绑定
            </span>
          )}
        </div>
        {bound && !unbinding && (
          <button type="button" className={ghostButtonClass} onClick={() => setUnbinding(true)}>
            解绑
          </button>
        )}
      </div>

      {bound ? (
        <p className="text-xs text-slate-600 break-all">{bound}</p>
      ) : (
        <p className="text-[11px] text-slate-400">
          绑定后可用来找回密码，也可以在忘记密码时自助重置。
        </p>
      )}

      {unbinding && (
        <div className="mt-3 space-y-2">
          <input
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder="输入当前密码确认解绑"
            autoComplete="current-password"
            className={inputClass}
          />
          <div className="flex gap-2">
            <button
              type="button"
              disabled={submitting}
              onClick={() => void handleUnbind()}
              className="h-9 rounded-xl bg-rose-500 px-3 text-[11px] font-semibold text-white disabled:opacity-60"
            >
              {submitting ? '处理中…' : '确认解绑'}
            </button>
            <button
              type="button"
              className={ghostButtonClass}
              onClick={() => {
                setUnbinding(false);
                setPassword('');
                setNotice(null);
              }}
            >
              取消
            </button>
          </div>
        </div>
      )}

      {!bound && (
        <form onSubmit={handleBind} className="mt-3 space-y-2">
          <div className="flex gap-2">
            <input
              type={channel === 'email' ? 'email' : 'tel'}
              value={target}
              onChange={(event) => setTarget(event.target.value)}
              placeholder={placeholder}
              className={inputClass}
            />
            <button
              type="button"
              disabled={sending || countdown > 0}
              onClick={() => void handleSend()}
              className={`${ghostButtonClass} h-11 shrink-0 px-3`}
            >
              {countdown > 0 ? `${countdown}s` : sending ? '发送中…' : '获取验证码'}
            </button>
          </div>
          <input
            type="text"
            inputMode="numeric"
            value={code}
            onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
            placeholder="6 位验证码"
            className={inputClass}
          />
          <button
            type="submit"
            disabled={submitting}
            className="h-9 rounded-xl px-3 text-[11px] font-semibold text-white disabled:opacity-60"
            style={{ background: 'var(--brand-gradient)' }}
          >
            {submitting ? '绑定中…' : `绑定${label}`}
          </button>
        </form>
      )}

      <div className="mt-2">
        <NoticeLine notice={notice} />
      </div>
    </div>
  );
}

export default function AccountPage() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<TabKey>('profile');

  const [nickname, setNickname] = useState('');
  const [avatar, setAvatar] = useState('');
  const [bio, setBio] = useState('');
  const [profileNotice, setProfileNotice] = useState<Notice | null>(null);
  const [savingProfile, setSavingProfile] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileInput = useRef<HTMLInputElement | null>(null);
  const [avatarHistory, setAvatarHistory] = useState<AvatarHistoryItem[]>([]);
  const [loadingAvatars, setLoadingAvatars] = useState(false);
  const [avatarBusyId, setAvatarBusyId] = useState<number | null>(null);

  const [oldPassword, setOldPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [pwdNotice, setPwdNotice] = useState<Notice | null>(null);
  const [savingPwd, setSavingPwd] = useState(false);

  const [contact, setContact] = useState<UserContact | null>(null);

  const [sessions, setSessions] = useState<LoginSession[]>([]);
  const [loadingSessions, setLoadingSessions] = useState(false);
  const [revokingId, setRevokingId] = useState('');

  const [deletePassword, setDeletePassword] = useState('');
  const [deleteConfirm, setDeleteConfirm] = useState('');
  const [deleteNotice, setDeleteNotice] = useState<Notice | null>(null);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    let alive = true;
    void (async () => {
      const me = await checkMe();
      if (!alive) return;
      setUser(me);
      if (me) {
        setNickname(me.nickname || me.username);
        // 只回填用户自己填写的头像，避免把已佩戴的装扮头像写回资料。
        setAvatar(me.profileAvatar || '');
        setBio(me.bio || '');
        const c = await getContact();
        if (alive) setContact(c);
      }
      setLoading(false);
    })();
    return () => {
      alive = false;
    };
  }, []);

  useEffect(() => {
    if (tab !== 'devices' || !user) return;
    let alive = true;
    setLoadingSessions(true);
    void (async () => {
      const list = await getSessions();
      if (!alive) return;
      setSessions(list);
      setLoadingSessions(false);
    })();
    return () => {
      alive = false;
    };
  }, [tab, user]);

  // 历史头像：进入个人资料页时拉取，最多 20 条（服务端超出后自动裁剪并删源文件）。
  useEffect(() => {
    if (tab !== 'profile' || !user) return;
    let alive = true;
    setLoadingAvatars(true);
    void (async () => {
      const list = await listAvatars();
      if (!alive) return;
      setAvatarHistory(list);
      setLoadingAvatars(false);
    })();
    return () => {
      alive = false;
    };
  }, [tab, user]);

  const avatarPreview = useMemo(() => {
    const trimmed = avatar.trim();
    return trimmed || user?.avatar || '/brand/bllii-symbol.svg';
  }, [avatar, user]);

  async function submitProfile(event: React.FormEvent) {
    event.preventDefault();
    if (savingProfile) return;
    const name = nickname.trim();
    if (!name || name.length > 20) {
      setProfileNotice({ text: '昵称需要 1 到 20 个字', error: true });
      return;
    }
    if (bio.trim().length > 80) {
      setProfileNotice({ text: '个人简介最多 80 个字', error: true });
      return;
    }
    setSavingProfile(true);
    setProfileNotice(null);
    try {
      const res = await updateProfile({ nickname: name, avatar: avatar.trim(), bio: bio.trim() });
      if (res.code === 1 && res.user) {
        setUser(res.user);
      } else if (res.code === 1) {
        const me = await checkMe();
        if (me) setUser(me);
      }
      if (res.code === 1) {
        setProfileNotice({ text: '资料已更新' });
      } else {
        setProfileNotice({ text: res.error || res.msg || '资料保存失败', error: true });
      }
    } finally {
      setSavingProfile(false);
    }
  }

  async function handleAvatarPick(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    if (!/^image\/(jpeg|png|webp|gif)$/.test(file.type)) {
      setProfileNotice({ text: '仅支持 JPG / PNG / WebP / GIF 图片', error: true });
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      setProfileNotice({ text: '图片不能超过 2MB', error: true });
      return;
    }
    setUploading(true);
    setProfileNotice(null);
    try {
      const res = await uploadAvatar(file);
      if (res.code === 1 && res.url) {
        setAvatar(res.url);
        const me = await checkMe();
        if (me) setUser(me);
        setAvatarHistory(await listAvatars());
        setProfileNotice({ text: '头像已上传并设为当前头像，可在下方历史头像里切回旧图' });
      } else {
        setProfileNotice({ text: res.error || res.msg || '头像上传失败', error: true });
      }
    } finally {
      setUploading(false);
    }
  }

  // 把历史头像切回当前头像：服务端立即生效，无需再点保存资料。
  async function handleUseAvatar(item: AvatarHistoryItem) {
    if (avatarBusyId !== null || item.current) return;
    setAvatarBusyId(item.id);
    setProfileNotice(null);
    try {
      const res = await useAvatar(item.id);
      if (res.code === 1) {
        const me = await checkMe();
        if (me) setUser(me);
        setAvatar(res.url || item.url);
        setProfileNotice({ text: '已切换为该头像' });
      } else {
        setProfileNotice({ text: res.error || res.msg || '切换头像失败', error: true });
      }
    } finally {
      setAvatarBusyId(null);
    }
  }

  // 删除历史头像：服务端会连带删除对象存储 / 磁盘上的源文件，不可恢复。
  async function handleDeleteAvatar(item: AvatarHistoryItem) {
    if (avatarBusyId !== null) return;
    if (item.current) {
      setProfileNotice({ text: '当前正在使用的头像不能删除，请先切换到其他头像', error: true });
      return;
    }
    const ok = window.confirm('删除后该头像的源文件会被一并清理，且无法恢复。确定删除吗？');
    if (!ok) return;
    setAvatarBusyId(item.id);
    setProfileNotice(null);
    try {
      const res = await deleteAvatar(item.id);
      if (res.code === 1) {
        setAvatarHistory((prev) => prev.filter((it) => it.id !== item.id));
        setProfileNotice({ text: '头像已删除，源文件同时清理' });
      } else {
        setProfileNotice({ text: res.error || res.msg || '删除头像失败', error: true });
      }
    } finally {
      setAvatarBusyId(null);
    }
  }

  async function submitPassword(event: React.FormEvent) {
    event.preventDefault();
    if (savingPwd) return;
    if (!oldPassword) {
      setPwdNotice({ text: '请输入当前密码', error: true });
      return;
    }
    if (newPassword.length < 6) {
      setPwdNotice({ text: '新密码长度不能少于 6 位', error: true });
      return;
    }
    if (newPassword !== confirmPassword) {
      setPwdNotice({ text: '两次输入的新密码不一致', error: true });
      return;
    }
    if (newPassword === oldPassword) {
      setPwdNotice({ text: '新密码不能与当前密码相同', error: true });
      return;
    }
    setSavingPwd(true);
    setPwdNotice(null);
    try {
      const res = await changePassword(oldPassword, newPassword);
      if (res.code === 1) {
        setOldPassword('');
        setNewPassword('');
        setConfirmPassword('');
        const revoked = res.revoked_sessions ?? 0;
        setPwdNotice({
          text: revoked > 0 ? `密码已更新，${revoked} 台其他设备已下线` : '密码已更新'
        });
      } else {
        setPwdNotice({ text: res.error || res.msg || '密码修改失败', error: true });
      }
    } finally {
      setSavingPwd(false);
    }
  }

  async function handleRevoke(session: LoginSession) {
    if (revokingId) return;
    setRevokingId(session.id);
    try {
      const ok = await revokeSession(session.id);
      if (ok) {
        setSessions((prev) => prev.filter((item) => item.id !== session.id));
      }
    } finally {
      setRevokingId('');
    }
  }

  async function handleDeleteAccount() {
    if (deleting) return;
    if (!deletePassword) {
      setDeleteNotice({ text: '请输入当前密码', error: true });
      return;
    }
    if (deleteConfirm.trim() !== '注销') {
      setDeleteNotice({ text: '请输入「注销」两个字以确认', error: true });
      return;
    }
    setDeleting(true);
    setDeleteNotice(null);
    try {
      const res = await deleteAccount(deletePassword);
      if (res.code === 1) {
        clearSession();
        setDeleteNotice({ text: '账号已注销，即将返回首页…' });
        window.setTimeout(() => {
          window.location.href = '/';
        }, 1200);
      } else {
        setDeleteNotice({ text: res.error || res.msg || '注销失败', error: true });
      }
    } finally {
      setDeleting(false);
    }
  }

  if (loading) {
    return (
      <Layout title="账号设置 — AniPocket" activeNav="追番">
        <div className="page-content">
          <div className="mx-auto w-full max-w-[980px] px-4 py-10 text-xs text-slate-400">正在读取账号信息…</div>
        </div>
      </Layout>
    );
  }

  if (!user) {
    return (
      <Layout title="账号设置 — AniPocket" activeNav="追番">
        <div className="page-content">
          <div className="mx-auto w-full max-w-[520px] px-4 py-16 text-center">
            <img src="/brand/bllii-symbol.svg" alt="" width={56} height={56} className="mx-auto mb-4" />
            <h1 className="text-base font-bold text-slate-800 mb-2">登录后管理你的账号</h1>
            <p className="text-xs text-slate-500 mb-6">修改资料、更换密码、查看登录设备，都需要先登录。</p>
            <a
              href="/login?redirect=/account"
              className="inline-flex h-11 items-center justify-center rounded-xl px-6 text-xs font-semibold text-white shadow-md"
              style={{ background: 'var(--brand-gradient)' }}
            >
              去登录
            </a>
          </div>
        </div>
      </Layout>
    );
  }

  return (
    <Layout title="账号设置 — AniPocket" activeNav="追番">
      <div className="page-content">
        <div className="mx-auto w-full max-w-[980px] px-4 py-6">
          <header className="mb-5 flex flex-wrap items-center gap-3">
            <img
              src={user.avatar || '/brand/bllii-symbol.svg'}
              alt=""
              width={56}
              height={56}
              className="h-14 w-14 rounded-full object-cover ring-2 ring-[#597bea]/30"
            />
            <div className="min-w-0">
              <h1 className="truncate text-base font-bold text-slate-800">{user.nickname || user.username}</h1>
              <p className="mt-0.5 text-[11px] text-slate-400">
                @{user.username} · 账号设置
              </p>
            </div>
          </header>

          <div className="mb-4 flex flex-wrap gap-2" role="tablist" aria-label="账号设置分区">
            {TABS.map((item) => (
              <button
                key={item.key}
                type="button"
                role="tab"
                aria-selected={tab === item.key}
                onClick={() => setTab(item.key)}
                className="page-pill"
              >
                {item.label}
              </button>
            ))}
          </div>

          <section className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
            {tab === 'profile' && (
              <form onSubmit={submitProfile} className="space-y-4">
                <div className="flex items-center gap-4">
                  <img
                    src={avatarPreview}
                    alt="头像预览"
                    width={64}
                    height={64}
                    className="h-16 w-16 rounded-full object-cover ring-2 ring-slate-100"
                  />
                  <div className="min-w-0 flex-1">
                    <label className={labelClass}>头像</label>
                    <div className="flex flex-wrap items-center gap-2">
                      <button
                        type="button"
                        disabled={uploading}
                        onClick={() => fileInput.current?.click()}
                        className={ghostButtonClass}
                      >
                        {uploading ? '上传中…' : '上传图片'}
                      </button>
                      <span className="text-[11px] text-slate-400">JPG / PNG / WebP / GIF，不超过 2MB</span>
                    </div>
                    <input
                      ref={fileInput}
                      type="file"
                      accept="image/jpeg,image/png,image/webp,image/gif"
                      onChange={(event) => void handleAvatarPick(event)}
                      className="hidden"
                    />
                    <input
                      type="text"
                      value={avatar}
                      onChange={(event) => setAvatar(event.target.value)}
                      placeholder="也可以直接填写 https:// 链接，留空使用默认头像"
                      className={`${inputClass} mt-2`}
                    />
                  </div>
                </div>

                <div>
                  <div className="mb-2 flex flex-wrap items-baseline justify-between gap-1">
                    <label className={`${labelClass} mb-0`}>历史头像</label>
                    <span className="text-[11px] text-slate-400">
                      最多保留 20 张 · 点「使用」立即切换，删除会同时清理源文件
                    </span>
                  </div>
                  {loadingAvatars ? (
                    <p className="text-[11px] text-slate-400">正在读取历史头像…</p>
                  ) : avatarHistory.length === 0 ? (
                    <p className="text-[11px] text-slate-400">
                      还没有上传过头像，上传后会自动保留在这里，方便随时切回。
                    </p>
                  ) : (
                    <div className="grid grid-cols-4 gap-2 sm:grid-cols-6 lg:grid-cols-8">
                      {avatarHistory.map((item) => (
                        <div
                          key={item.id}
                          className={`relative rounded-xl border p-1 transition-all ${
                            item.current
                              ? 'border-[#597bea] ring-2 ring-blue-500/20'
                              : 'border-slate-200 hover:border-slate-300'
                          }`}
                        >
                          <img
                            src={item.url}
                            alt="历史头像"
                            className="aspect-square w-full rounded-lg bg-slate-50 object-cover"
                          />
                          {item.current && (
                            <span className="absolute left-1.5 top-1.5 rounded-md bg-[#597bea] px-1 py-0.5 text-[9px] font-semibold leading-tight text-white">
                              使用中
                            </span>
                          )}
                          <div className="mt-1 flex items-center justify-between gap-1 px-0.5">
                            <button
                              type="button"
                              disabled={item.current || avatarBusyId !== null}
                              onClick={() => void handleUseAvatar(item)}
                              className="text-[10px] font-semibold text-[#597bea] transition-colors disabled:text-slate-300"
                            >
                              使用
                            </button>
                            <button
                              type="button"
                              disabled={item.current || avatarBusyId !== null}
                              onClick={() => void handleDeleteAvatar(item)}
                              className="text-[10px] font-semibold text-rose-500 transition-colors disabled:text-slate-300"
                            >
                              删除
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                <div>
                  <label className={labelClass}>昵称</label>
                  <input
                    type="text"
                    value={nickname}
                    onChange={(event) => setNickname(event.target.value)}
                    placeholder="1 到 20 个字"
                    maxLength={20}
                    className={inputClass}
                  />
                </div>

                <div>
                  <label className={labelClass}>个人简介</label>
                  <textarea
                    value={bio}
                    onChange={(event) => setBio(event.target.value)}
                    placeholder="介绍一下自己，最多 80 个字"
                    maxLength={80}
                    rows={3}
                    className={`${inputClass} h-auto py-3 leading-relaxed resize-none`}
                  />
                  <p className="mt-1 text-[11px] text-slate-400">{bio.trim().length} / 80</p>
                </div>

                <NoticeLine notice={profileNotice} />

                <button
                  type="submit"
                  disabled={savingProfile}
                  className={primaryButtonClass}
                  style={{ background: 'var(--brand-gradient)' }}
                >
                  {savingProfile ? '保存中…' : '保存资料'}
                </button>
              </form>
            )}

            {tab === 'security' && (
              <div className="space-y-6">
                <form onSubmit={submitPassword} className="max-w-[420px] space-y-4">
                  <h2 className="text-xs font-bold text-slate-800">修改密码</h2>
                  <div>
                    <label className={labelClass}>当前密码</label>
                    <input
                      type="password"
                      value={oldPassword}
                      onChange={(event) => setOldPassword(event.target.value)}
                      placeholder="请输入当前登录密码"
                      autoComplete="current-password"
                      className={inputClass}
                    />
                  </div>
                  <div>
                    <label className={labelClass}>新密码</label>
                    <input
                      type="password"
                      value={newPassword}
                      onChange={(event) => setNewPassword(event.target.value)}
                      placeholder="至少 6 位，不能与原密码相同"
                      autoComplete="new-password"
                      className={inputClass}
                    />
                  </div>
                  <div>
                    <label className={labelClass}>确认新密码</label>
                    <input
                      type="password"
                      value={confirmPassword}
                      onChange={(event) => setConfirmPassword(event.target.value)}
                      placeholder="再次输入新密码"
                      autoComplete="new-password"
                      className={inputClass}
                    />
                  </div>

                  <NoticeLine notice={pwdNotice} />

                  <p className="text-[11px] leading-relaxed text-slate-400">
                    修改成功后，其他已登录设备会被自动下线，当前设备保持登录。
                  </p>

                  <button
                    type="submit"
                    disabled={savingPwd}
                    className={primaryButtonClass}
                    style={{ background: 'var(--brand-gradient)' }}
                  >
                    {savingPwd ? '提交中…' : '更新密码'}
                  </button>
                </form>

                <div className="border-t border-slate-100 pt-5">
                  <h2 className="mb-1 text-xs font-bold text-slate-800">联系方式</h2>
                  <p className="mb-3 text-[11px] text-slate-400">
                    绑定邮箱或手机后，忘记密码时可以自助找回。
                  </p>
                  <div className="grid gap-3 md:grid-cols-2">
                    <ContactCard
                      channel="email"
                      label="邮箱"
                      placeholder="you@example.com"
                      contact={contact}
                      onChanged={setContact}
                    />
                    <ContactCard
                      channel="phone"
                      label="手机号"
                      placeholder="11 位手机号"
                      contact={contact}
                      onChanged={setContact}
                    />
                  </div>
                </div>

                <div className="rounded-xl border border-rose-200 bg-rose-50/60 p-4">
                  <h2 className="text-xs font-bold text-rose-600">注销账号</h2>
                  <p className="mt-1 text-[11px] leading-relaxed text-rose-500/90">
                    注销后账号不可恢复：用户名会被匿名化，邮箱 / 手机 / 头像 / 简介将被清空，
                    所有设备立即下线。已发布的内容会保留，作者显示为「已注销用户」。
                  </p>
                  <div className="mt-3 grid gap-2 md:grid-cols-2">
                    <input
                      type="password"
                      value={deletePassword}
                      onChange={(event) => setDeletePassword(event.target.value)}
                      placeholder="当前密码"
                      autoComplete="current-password"
                      className={inputClass}
                    />
                    <input
                      type="text"
                      value={deleteConfirm}
                      onChange={(event) => setDeleteConfirm(event.target.value)}
                      placeholder="输入「注销」以确认"
                      className={inputClass}
                    />
                  </div>
                  <div className="mt-2">
                    <NoticeLine notice={deleteNotice} />
                  </div>
                  <button
                    type="button"
                    disabled={deleting}
                    onClick={() => void handleDeleteAccount()}
                    className="mt-3 h-9 rounded-xl bg-rose-500 px-3 text-[11px] font-semibold text-white disabled:opacity-60"
                  >
                    {deleting ? '处理中…' : '永久注销账号'}
                  </button>
                </div>
              </div>
            )}

            {tab === 'devices' && (
              <div>
                <div className="mb-3 flex items-center justify-between gap-3">
                  <div>
                    <h2 className="text-xs font-bold text-slate-800">登录设备</h2>
                    <p className="mt-0.5 text-[11px] text-slate-400">发现不认识的设备，立即让它下线。</p>
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      if (!user) return;
                      setLoadingSessions(true);
                      void getSessions().then((list) => {
                        setSessions(list);
                        setLoadingSessions(false);
                      });
                    }}
                    className="h-9 rounded-xl border border-slate-200 px-3 text-[11px] font-semibold text-slate-600 hover:border-[#597bea] hover:text-[#597bea]"
                  >
                    刷新
                  </button>
                </div>

                {loadingSessions ? (
                  <p className="py-6 text-center text-xs text-slate-400">正在读取登录设备…</p>
                ) : sessions.length === 0 ? (
                  <p className="py-6 text-center text-xs text-slate-400">暂无其他登录记录。</p>
                ) : (
                  <ul className="divide-y divide-slate-100">
                    {sessions.map((session) => (
                      <li key={session.id} className="flex flex-wrap items-center gap-3 py-3">
                        <span className="flex h-9 w-9 items-center justify-center rounded-full bg-slate-50 text-slate-400">
                          <BrandIcon name="user" size={16} />
                        </span>
                        <div className="min-w-0 flex-1">
                          <p className="flex items-center gap-2 text-xs font-semibold text-slate-700">
                            {describeAgent(session.user_agent)}
                            {session.current && (
                              <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-[10px] font-semibold text-emerald-600">
                                当前设备
                              </span>
                            )}
                          </p>
                          <p className="mt-0.5 text-[11px] text-slate-400">
                            {session.ip || '未知 IP'} · 登录于 {formatTime(session.created_at)}
                          </p>
                        </div>
                        {!session.current && (
                          <button
                            type="button"
                            disabled={revokingId === session.id}
                            onClick={() => void handleRevoke(session)}
                            className="h-9 rounded-xl border border-rose-200 px-3 text-[11px] font-semibold text-rose-500 hover:bg-rose-50 disabled:opacity-50"
                          >
                            {revokingId === session.id ? '处理中…' : '下线'}
                          </button>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </section>
        </div>
      </div>
    </Layout>
  );
}
