import React, { useEffect, useRef, useState } from 'react';
import BrandIcon from './BrandIcon';
import { getUser } from '../lib/auth';
import {
  WatchTogetherClient,
  WatchMemberView,
  WatchSnapshot,
} from '../lib/watch-together';

interface Props {
  watch: WatchTogetherClient;
  videoId: number;
  videoName: string;
  /** 聊天实时弹幕开关（由播放页持久化）。 */
  danmakuOn: boolean;
  onToggleDanmaku: () => void;
  currentGroupIndex: () => number;
  currentEpisodeIndex: () => number;
  currentEpisodeName: () => string;
}

/** 一起看面板：建房 / 房间码加入 / 成员 / 房间聊天，嵌在播放页右栏。 */
export default function WatchTogetherPanel({
  watch,
  videoId,
  videoName,
  danmakuOn,
  onToggleDanmaku,
  currentGroupIndex,
  currentEpisodeIndex,
  currentEpisodeName,
}: Props) {
  const [, setTick] = useState(0);
  const [codeInput, setCodeInput] = useState('');
  const [chatInput, setChatInput] = useState('');
  const [busy, setBusy] = useState(false);
  const [allowAllControl, setAllowAllControl] = useState(false);
  const chatBottomRef = useRef<HTMLDivElement>(null);
  const lastNoticeRef = useRef('');

  // 订阅同步引擎状态（subscribe 返回取消订阅函数，卸载时干净退订，
  // 不再覆盖全局 onChange 影响播放页的订阅）
  useEffect(() => {
    return watch.subscribe(() => setTick((t) => t + 1));
  }, [watch]);

  useEffect(() => {
    chatBottomRef.current?.scrollIntoView({ block: 'nearest' });
  }, [watch.messages.length]);

  const loggedIn = !!getUser();

  const run = async (action: () => Promise<void>) => {
    if (busy) return;
    setBusy(true);
    try {
      await action();
    } catch (err) {
      watch.notify(err instanceof Error ? err.message : '操作失败，请稍后重试');
    } finally {
      setBusy(false);
    }
  };

  const handleCreate = () =>
    run(async () => {
      await watch.create(
        videoId,
        currentGroupIndex(),
        currentEpisodeIndex(),
        allowAllControl ? 'all' : 'host'
      );
    });

  const handleJoin = () =>
    run(async () => {
      if (codeInput.trim().length !== 6) {
        watch.notify('请输入 6 位房间码');
        return;
      }
      await watch.join(codeInput);
      setCodeInput('');
    });

  const handleSend = () =>
    run(async () => {
      const content = chatInput.trim();
      if (!content) return;
      setChatInput('');
      await watch.chat(content);
    });

  const handleLeave = () =>
    run(async () => {
      await watch.leave();
    });

  const copyCode = async (code: string) => {
    try {
      await navigator.clipboard.writeText(code);
    } catch {}
  };

  const transferHost = (member: WatchMemberView) =>
    run(async () => {
      await watch.transferHost(member.user_id);
    });

  const toggleControlMode = (currentMode: string) =>
    run(async () => {
      await watch.setControlMode(currentMode === 'all' ? 'host' : 'all');
    });

  const cardClass =
    'rounded-2xl p-4 shadow-sm border border-slate-100 bg-white flex-1 flex flex-col transition-colors';
  const notice =
    watch.lastNotice && watch.lastNotice !== lastNoticeRef.current
      ? watch.lastNotice
      : '';
  if (watch.lastNotice) lastNoticeRef.current = watch.lastNotice;

  if (!loggedIn) {
    return (
      <div className={cardClass}>
        <PanelHeading />
        <p className="text-xs text-slate-500 leading-relaxed mt-2">
          一起看需要登录账号。登录后在这里创建房间，或用房间码加入朋友的房间，进度会自动同步。
        </p>
        <a
          href={loginHref()}
          className="mt-3 inline-flex items-center justify-center gap-1.5 px-4 py-2 rounded-xl bg-[#597bea] text-white text-xs font-bold hover:bg-blue-600 transition-colors"
        >
          去登录
        </a>
      </div>
    );
  }

  if (!watch.active) {
    return (
      <div className={cardClass}>
        <PanelHeading />
        <p className="text-xs text-slate-500 leading-relaxed mt-2">
          房主控制播放、拖进度、切集，所有人自动跟随；房间消息只有成员可见。
        </p>
        {/* 建房时选择控制权限 */}
        <button
          type="button"
          onClick={() => setAllowAllControl(!allowAllControl)}
          className="mt-3 w-full flex items-center justify-between gap-2 px-3 py-2.5 rounded-xl border border-slate-200 cursor-pointer hover:bg-slate-50 transition-colors text-left"
        >
          <span>
            <span className="block text-xs font-bold text-slate-700">
              允许所有人控制播放
            </span>
            <span className="block text-[11px] text-slate-400 mt-0.5">
              关闭时只有你能操作播放，开启后成员也可以
            </span>
          </span>
          <span
            className={`relative inline-block w-9 h-5 rounded-full transition-colors shrink-0 ${
              allowAllControl ? 'bg-[#597bea]' : 'bg-slate-200'
            }`}
          >
            <span
              className={`absolute top-0.5 w-4 h-4 rounded-full bg-white shadow transition-all ${
                allowAllControl ? 'left-[18px]' : 'left-0.5'
              }`}
            />
          </span>
        </button>
        <button
          type="button"
          onClick={handleCreate}
          disabled={busy}
          className="mt-2.5 w-full inline-flex items-center justify-center gap-1.5 px-4 py-2.5 rounded-xl bg-[#597bea] text-white text-sm font-bold hover:bg-blue-600 transition-colors cursor-pointer disabled:opacity-50"
        >
          <BrandIcon name="play" size={16} />
          <span>{busy ? '创建中…' : '为当前影片创建房间'}</span>
        </button>
        <p className="text-[11px] text-slate-400 mt-1.5 text-center truncate">
          {videoName} · {currentEpisodeName()}
        </p>

        <div className="flex items-center gap-2 my-3">
          <div className="flex-1 h-px bg-slate-100" />
          <span className="text-[11px] text-slate-400">已有房间？</span>
          <div className="flex-1 h-px bg-slate-100" />
        </div>

        <div className="flex items-center gap-2">
          <input
            value={codeInput}
            onChange={(e) =>
              setCodeInput(e.target.value.toUpperCase().slice(0, 6))
            }
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleJoin();
            }}
            placeholder="房间码"
            maxLength={6}
            className="flex-1 min-w-0 px-3 py-2 rounded-xl border border-slate-200 text-sm font-bold tracking-[0.3em] focus:outline-none focus:border-blue-400"
          />
          <button
            type="button"
            onClick={handleJoin}
            disabled={busy}
            className="px-4 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-700 text-sm font-bold transition-colors cursor-pointer disabled:opacity-50"
          >
            加入
          </button>
        </div>
        {notice && <p className="text-xs text-rose-500 mt-2">{notice}</p>}
      </div>
    );
  }

  const snap = watch.snapshot as WatchSnapshot;
  const controlLabel = snap.control_mode === 'all' ? '所有人可控制' : '仅房主控制';
  const statusLine = watch.isHost
    ? snap.control_mode === 'all'
      ? '你是房主 · 所有人可控制'
      : '你是房主，大家跟着你走'
    : snap.control_mode === 'all'
    ? '所有人可控制播放'
    : '房主控制播放中';

  return (
    <div className={cardClass}>
      <div className="flex items-center gap-2 flex-wrap">
        <BrandIcon name="smile" size={16} className="text-rose-500" />
        {/* 控制权限 chip：房主可点击切换 */}
        <button
          type="button"
          onClick={() => watch.isHost && toggleControlMode(snap.control_mode)}
          title={watch.isHost ? '点击切换控制权限' : undefined}
          className={`px-2 py-0.5 rounded-lg text-[11px] font-bold transition-colors ${
            snap.control_mode === 'all'
              ? 'bg-emerald-50 text-emerald-600'
              : 'bg-blue-50 text-blue-600'
          } ${watch.isHost ? 'cursor-pointer hover:opacity-80' : 'cursor-default'}`}
        >
          {controlLabel}
          {watch.isHost ? ' ⇄' : ''}
        </button>
        <button
          type="button"
          onClick={() => copyCode(snap.code)}
          className="shrink-0 ml-auto px-2.5 py-1 rounded-lg bg-gradient-to-r from-[#FF89C7] via-[#AE8CFF] to-[#80B6FF] text-white text-xs font-black tracking-widest cursor-pointer"
          title="点击复制房间码"
        >
          {snap.code}
        </button>
        <button
          type="button"
          onClick={handleLeave}
          disabled={busy}
          className="shrink-0 p-1.5 rounded-lg bg-slate-100 text-slate-500 hover:bg-slate-200 transition-colors cursor-pointer"
          title="退出房间"
        >
          <BrandIcon name="logout" size={14} />
        </button>
      </div>
      <p className="text-[11px] text-slate-400 mt-1 truncate">
        {statusLine} · {snap.title}
      </p>

      {/* 成员 */}
      <div className="flex items-center flex-wrap gap-1.5 mt-2">
        {snap.members.map((member) => (
          <button
            key={member.user_id}
            type="button"
            onClick={() => {
              if (watch.isHost && !member.is_host) transferHost(member);
            }}
            title={
              watch.isHost && !member.is_host
                ? `把房主转让给 ${member.nickname}`
                : member.nickname
            }
            className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-lg text-xs font-semibold transition-colors ${
              member.is_host
                ? 'bg-amber-100 text-amber-700'
                : 'bg-slate-50 text-slate-600'
            } ${watch.isHost && !member.is_host ? 'hover:bg-slate-100 cursor-pointer' : 'cursor-default'}`}
          >
            {member.is_host && (
              <span className="bg-amber-500 text-white text-[10px] font-black px-1.5 py-px rounded">
                房主
              </span>
            )}
            <span className="max-w-[72px] truncate">{member.nickname}</span>
          </button>
        ))}
      </div>

      {/* 聊天 */}
      <div className="mt-2.5 flex-1 min-h-0 flex flex-col">
        <div className="flex-1 min-h-[180px] max-h-[340px] overflow-y-auto pr-1 space-y-2 scrollbar-thin">
          {watch.messages.length === 0 && (
            <p className="text-xs text-slate-400 text-center py-4">
              聊点什么吧～消息会以实时弹幕飘在画面上
            </p>
          )}
          {watch.messages.map((msg) => {
            const fromHost = msg.user_id === snap.host_id;
            const own = watch.myUserId != null && msg.user_id === watch.myUserId;
            return (
              <div key={msg.id}>
                <div className="flex items-center gap-1">
                  {fromHost && (
                    <span className="bg-amber-500 text-white text-[10px] font-black px-1.5 py-px rounded">
                      房主
                    </span>
                  )}
                  <span
                    className={`text-[11px] font-bold ${
                      own
                        ? 'text-[#ec6bab]'
                        : fromHost
                        ? 'text-blue-600'
                        : 'text-slate-400'
                    }`}
                  >
                    {own ? '我' : msg.author_name}
                  </span>
                </div>
                <div
                  className={`inline-block mt-0.5 px-2.5 py-1.5 rounded-xl text-xs leading-relaxed border ${
                    own
                      ? 'rounded-tl-sm bg-pink-50 border-pink-100 text-slate-700'
                      : 'rounded-tl-sm bg-slate-50 border-slate-100 text-slate-700'
                  }`}
                >
                  {msg.content}
                </div>
              </div>
            );
          })}
          <div ref={chatBottomRef} />
        </div>

        <div className="flex items-center gap-2 mt-2">
          <input
            value={chatInput}
            onChange={(e) => setChatInput(e.target.value.slice(0, 100))}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleSend();
            }}
            placeholder="和房间里的人聊聊…"
            maxLength={100}
            className="flex-1 min-w-0 px-3 py-2 rounded-xl border border-slate-200 text-xs focus:outline-none focus:border-blue-400"
          />
          <button
            type="button"
            onClick={handleSend}
            disabled={busy}
            className="p-2 rounded-xl bg-[#597bea] text-white hover:bg-blue-600 transition-colors cursor-pointer disabled:opacity-50"
            title="发送"
          >
            <BrandIcon name="send" size={15} />
          </button>
        </div>
        {notice && <p className="text-xs text-rose-500 mt-1.5">{notice}</p>}
      </div>

      {/* 聊天弹幕开关 */}
      <button
        type="button"
        onClick={onToggleDanmaku}
        className="mt-2.5 w-full flex items-center justify-between gap-2 px-3 py-2 rounded-xl border border-slate-100 bg-slate-50/60 cursor-pointer hover:bg-slate-100 transition-colors"
        title="开关一起看聊天弹幕"
      >
        <span className="flex items-center gap-1.5 text-[11px] font-bold text-slate-600">
          <BrandIcon name="message" size={13} className="text-[#FF89C7]" />
          聊天弹幕
          <span className="font-normal text-slate-400">消息飘在画面上</span>
        </span>
        <span
          className={`relative inline-block w-8 h-[18px] rounded-full transition-colors shrink-0 ${
            danmakuOn ? 'bg-[#FF89C7]' : 'bg-slate-200'
          }`}
        >
          <span
            className={`absolute top-0.5 w-3.5 h-3.5 rounded-full bg-white shadow transition-all ${
              danmakuOn ? 'left-[16px]' : 'left-0.5'
            }`}
          />
        </span>
      </button>
    </div>
  );
}

function loginHref() {
  if (typeof window === 'undefined') return '/login';
  return `/login?redirect=${encodeURIComponent(
    window.location.pathname + window.location.search
  )}`;
}

function PanelHeading() {
  return (
    <h3 className="text-sm font-bold text-slate-800 flex items-center gap-1.5">
      <BrandIcon name="smile" size={16} className="text-rose-500" />
      <span>一起看</span>
      <span className="text-[11px] font-normal text-slate-400">
        和朋友同步追番
      </span>
    </h3>
  );
}
