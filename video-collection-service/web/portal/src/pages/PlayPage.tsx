import React, { useState, useEffect, useRef } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import VideoCard from '../components/VideoCard';
import WatchTogetherPanel from '../components/WatchTogetherPanel';
import WatchDanmakuOverlay, {
  type WatchDanmakuOverlayHandle,
} from '../components/WatchDanmakuOverlay';
import {
  getVideoDetail,
  type VideoRecord,
  type PlayGroup,
  type Episode,
} from '../lib/api';
import { getUser, getFavorites, addFavorite, removeFavorite } from '../lib/auth';
import {
  WatchTogetherClient,
  type WatchSnapshot,
} from '../lib/watch-together';

interface Props {
  id?: string;
  video?: VideoRecord;
  related?: VideoRecord[];
}

declare global {
  interface Window {
    videojs?: any;
    ModernVideoPlayer?: any;
    blliiTrack?: any;
  }
}

export default function PlayPage({ id = '317', video: initialVideo, related: initialRelated }: Props) {
  const [video, setVideo] = useState<VideoRecord | null>(initialVideo || null);
  const [related, setRelated] = useState<VideoRecord[]>(initialRelated || []);
  const [selectedGroupIdx, setSelectedGroupIdx] = useState(0);
  const [selectedEpIdx, setSelectedEpIdx] = useState(0);
  const [loading, setLoading] = useState(!initialVideo);
  const [isFocusMode, setIsFocusMode] = useState(false);
  const [isFavorite, setIsFavorite] = useState(false);
  const [synopsisExpanded, setSynopsisExpanded] = useState(false);

  const playerContainerRef = useRef<HTMLDivElement>(null);
  const modernPlayerRef = useRef<any>(null);

  // 一起看：同步引擎与选集索引镜像（避免闭包拿到旧值）
  const watchRef = useRef<WatchTogetherClient | null>(null);
  const selectedGroupIdxRef = useRef(0);
  const selectedEpIdxRef = useRef(0);
  const [, setWatchTick] = useState(0);

  // 一起看聊天实时弹幕：开关持久化，弹幕层挂载在播放器舞台内
  const watchDanmakuRef = useRef<WatchDanmakuOverlayHandle>(null);
  const [watchDanmakuOn, setWatchDanmakuOn] = useState(true);
  useEffect(() => {
    try {
      const saved = localStorage.getItem('bllii_watch_danmaku');
      if (saved !== null) setWatchDanmakuOn(saved === '1');
    } catch {}
  }, []);
  const toggleWatchDanmaku = () => {
    setWatchDanmakuOn((prev) => {
      const next = !prev;
      try {
        localStorage.setItem('bllii_watch_danmaku', next ? '1' : '0');
      } catch {}
      return next;
    });
  };

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const client = new WatchTogetherClient();
    client.myUserId = getUser()?.id ?? null;
    client.getPositionMs = () => {
      const vj = modernPlayerRef.current?.player;
      return vj ? (vj.currentTime() || 0) * 1000 : 0;
    };
    client.isPlaying = () => {
      const vj = modernPlayerRef.current?.player;
      return vj ? !vj.paused() : false;
    };
    client.getGroupIndex = () =>
      modernPlayerRef.current?.currentRouteIndex ?? selectedGroupIdxRef.current;
    client.getEpisodeIndex = () =>
      modernPlayerRef.current?.currentEpisodeIndex ?? selectedEpIdxRef.current;
    client.onNotify = (message) => {
      console.info('[watch]', message);
    };
    // 聊天消息送上实时弹幕（与客户端一致）：自己的消息用品牌粉区分
    client.onChatArrived = (msg, own) => {
      watchDanmakuRef.current?.push({
        id: msg.id,
        text: `${msg.author_name}：${msg.content}`,
        color: own ? '#FF89C7' : undefined,
      });
    };
    client.onChange = () => {
      setWatchTick((t) => t + 1);
      syncWatchControls();
    };
    client.applyRemote = (snap) => applyWatchRemote(snap);
    watchRef.current = client;
    return () => {
      client.destroy();
      watchRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /** 应用远端播放状态：倍速 / 切集 / 播放暂停 / 进度对齐。 */
  const applyWatchRemote = (snap: WatchSnapshot) => {
    const mp = modernPlayerRef.current;
    const vj = mp?.player;
    if (!mp || !vj) return;
    const watch = watchRef.current;
    try {
      const currentRate = typeof vj.playbackRate === 'function' ? vj.playbackRate() || 1 : 1;
      if (snap.rate > 0 && Math.abs(currentRate - snap.rate) > 0.01) {
        vj.playbackRate(snap.rate);
      }
    } catch {}
    const epChanged =
      snap.group_index !== mp.currentRouteIndex ||
      snap.episode_index !== mp.currentEpisodeIndex;
    if (epChanged) {
      try {
        mp.playEpisode(snap.group_index, snap.episode_index);
      } catch {}
      // 媒体加载完成前 currentTime 赋值会被忽略：挂起，loadedmetadata 时对齐
      if (watch) {
        watch.pendingSeek = { ms: snap.target_position_ms, playing: snap.playing };
      }
      window.setTimeout(() => applyPendingSeek(), 2500);
      return;
    }
    try {
      if (snap.playing) {
        // 浏览器自动播放策略可能拦截 play()：被拒时静音重试（静音自动播放始终允许），
        // 否则成员会永远停在 0:00 不跟。
        const attempt = vj.play();
        if (attempt && typeof attempt.catch === 'function') {
          attempt.catch(() => {
            try {
              if (!vj.muted()) {
                vj.muted(true);
                const retry = vj.play();
                if (retry && typeof retry.catch === 'function') retry.catch(() => {});
                if (watch) watch.notify('已自动静音以保持同步，点击播放器可取消静音');
              }
            } catch {}
          });
        }
      } else {
        vj.pause();
      }
      const ready = typeof vj.readyState === 'function' ? vj.readyState() : 4;
      if (ready >= 1) {
        vj.currentTime(snap.target_position_ms / 1000);
      } else if (watch) {
        watch.pendingSeek = { ms: snap.target_position_ms, playing: snap.playing };
      }
    } catch {}
  };

  /** 媒体就绪后应用挂起的远端进度对齐。 */
  const applyPendingSeek = () => {
    const watch = watchRef.current;
    const pending = watch?.pendingSeek;
    const vj = modernPlayerRef.current?.player;
    if (!pending || !vj) return;
    try {
      const ready = typeof vj.readyState === 'function' ? vj.readyState() : 4;
      if (ready < 1) return; // 仍未就绪，等下一次 loadedmetadata
      vj.currentTime(pending.ms / 1000);
      if (pending.playing) vj.play();
      else vj.pause();
      watch!.pendingSeek = null;
    } catch {}
  };

  /** 成员视角：选集 / 线路控制交给房主。 */
  const watchGuestLocked = () => {
    const watch = watchRef.current;
    if (watch && watch.active && !watch.canControl) {
      watch.notify('房主控制中');
      return true;
    }
    return false;
  };

  /** 无控制权的成员隐藏播放键与进度条（音量、全屏等本地控制保留）。 */
  const syncWatchControls = () => {
    const watch = watchRef.current;
    const vj = modernPlayerRef.current?.player;
    if (!vj) return;
    const controlBar = typeof vj.getChild === 'function' ? vj.getChild('controlBar') : null;
    if (!controlBar) return;
    const canControl = watch ? watch.canControl : true;
    for (const name of ['playToggle', 'progressControl']) {
      const child = typeof controlBar.getChild === 'function' ? controlBar.getChild(name) : null;
      if (!child) continue;
      try {
        if (canControl) child.show();
        else child.hide();
      } catch {}
    }
  };

  /** 一起看事件：有控制权则推送状态；无控制权则回弹本地越权操作，跟随房主。 */
  const handleWatchLiveEvent = (
    vj: any,
    kind: 'play' | 'pause' | 'seeked'
  ) => {
    const watch = watchRef.current;
    if (!watch || !watch.active || watch.applyingRemote) return;
    if (watch.canControl) {
      void watch.pushState({
        playing: !vj.paused(),
        position_ms: Math.round((vj.currentTime() || 0) * 1000),
        rate:
          typeof vj.playbackRate === 'function' ? vj.playbackRate() || 1 : 1,
      });
      return;
    }
    // 无控制权：本地播放/暂停/拖动在约 2 秒内被拉回房主状态，这里立即回弹。
    const snap = watch.snapshot;
    if (!snap) return;
    let reverted = false;
    try {
      if (snap.playing && vj.paused()) {
        reverted = true;
        vj.play();
      } else if (!snap.playing && !vj.paused()) {
        reverted = true;
        vj.pause();
      }
      const drift = snap.target_position_ms / 1000 - (vj.currentTime() || 0);
      if (Math.abs(drift) > 1.5) {
        reverted = true;
        vj.currentTime(snap.target_position_ms / 1000);
      }
    } catch {}
    if (reverted) watch.notify('房主控制中');
  };

  // 1. 数据获取（若 SSR 未直接提供或切换了 id）
  useEffect(() => {
    if (!initialVideo || (video && String(video.id) !== String(id))) {
      setLoading(true);
      getVideoDetail(id)
        .then((detail) => {
          if (detail && detail.video) {
            setVideo(detail.video);
            if (detail.related && detail.related.length > 0) {
              setRelated(detail.related);
            }
          }
        })
        .catch(() => {})
        .finally(() => setLoading(false));
    }
  }, [id, initialVideo]);

  // 2. 检查用户收藏追番状态
  useEffect(() => {
    if (typeof window === 'undefined' || !video) return;
    const user = getUser();
    if (!user) return;
    getFavorites()
      .then((favs) => {
        setIsFavorite(favs.some((f) => f.video_id === Number(video.id)));
      })
      .catch(() => {});
  }, [video?.id]);

  // 3. 现代化播放器核心脚本加载与实例化
  useEffect(() => {
    if (typeof window === 'undefined' || !video) return;

    // 确保 Video.js 核心样式表已加载
    if (!document.querySelector('link[href*="video-js"]')) {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = '/players/videojs/video-js.min.css';
      document.head.appendChild(link);
    }

    // 动态脚本加载助手
    const loadScript = (src: string): Promise<void> => {
      return new Promise((resolve, reject) => {
        const existing = document.querySelector(`script[src="${src}"]`);
        if (existing) {
          resolve();
          return;
        }
        const s = document.createElement('script');
        s.src = src;
        s.async = false;
        s.onload = () => resolve();
        s.onerror = reject;
        document.body.appendChild(s);
      });
    };

    let isMounted = true;

    const initPlayerEngine = async () => {
      try {
        if (!window.videojs) {
          await loadScript('/players/videojs/video.min.js');
        }
        if (!window.ModernVideoPlayer) {
          await loadScript('/players/videojs/modern-player.js');
        }

        if (!isMounted) return;

        // 确保容器内存在 video-js 目标 DOM
        if (playerContainerRef.current) {
          let el = document.getElementById('vplayer-element');
          if (!el) {
            playerContainerRef.current.innerHTML =
              '<video-js id="vplayer-element" class="video-js vjs-big-play-centered vjs-fill"></video-js>';
          }
        }

        // 解析 URL 参数与历史记录以恢复进度
        const p = new URLSearchParams(window.location.search);
        const historyKey = `vplayer_history_${video.id}`;
        let savedHistory: any = {};
        try {
          savedHistory = JSON.parse(localStorage.getItem(historyKey) || '{}') || {};
        } catch {}

        let initEp = 0;
        let initRoute = 0;
        if (p.has('ep')) {
          initEp = parseInt(p.get('ep') || '0', 10);
        } else if (typeof savedHistory.episodeIndex === 'number' && savedHistory.episodeIndex >= 0) {
          initEp = savedHistory.episodeIndex;
        }

        if (p.has('route')) {
          initRoute = parseInt(p.get('route') || '0', 10);
        } else if (typeof savedHistory.routeIndex === 'number' && savedHistory.routeIndex >= 0) {
          initRoute = savedHistory.routeIndex;
        }

        const resumeTime =
          savedHistory.episodeIndex === initEp && savedHistory.currentTime
            ? savedHistory.currentTime
            : 0;

        setSelectedGroupIdx(initRoute);
        setSelectedEpIdx(initEp);
        selectedGroupIdxRef.current = initRoute;
        selectedEpIdxRef.current = initEp;

        // 如果已存在旧实例，安全销毁
        if (modernPlayerRef.current) {
          try {
            modernPlayerRef.current.destroy();
          } catch {}
          modernPlayerRef.current = null;
        }

        // 实例化现代化播放器引擎
        const player = new window.ModernVideoPlayer('vplayer-element', {
          autoplay: true,
          autoplayNextDefault: true,
          nextCountdownSec: 3,
          initialTime: resumeTime,
          onEpisodeChange: (rIdx: number, epIdx: number, ep: any) => {
            setSelectedGroupIdx(rIdx);
            setSelectedEpIdx(epIdx);
            selectedGroupIdxRef.current = rIdx;
            selectedEpIdxRef.current = epIdx;

            // 一起看：无控制权成员的非远端切集（如自动连播）立即拉回房主进度
            const watchClient = watchRef.current;
            if (
              watchClient &&
              watchClient.active &&
              !watchClient.canControl &&
              !watchClient.applyingRemote &&
              watchClient.snapshot &&
              (watchClient.snapshot.group_index !== rIdx ||
                watchClient.snapshot.episode_index !== epIdx)
            ) {
              try {
                modernPlayerRef.current?.playEpisode(
                  watchClient.snapshot.group_index,
                  watchClient.snapshot.episode_index
                );
              } catch {}
              return;
            }
            // 有控制权者切集后推送状态
            if (watchClient && watchClient.canControl && !watchClient.applyingRemote) {
              void watchClient.pushState({
                group_index: rIdx,
                episode_index: epIdx,
                playing: true,
                position_ms: 0,
              });
            }

            // 无刷新同步 URL 参数
            const newUrl = new URL(window.location.href);
            newUrl.searchParams.set('ep', String(epIdx));
            if (rIdx > 0) {
              newUrl.searchParams.set('route', String(rIdx));
            } else {
              newUrl.searchParams.delete('route');
            }
            window.history.replaceState({}, '', newUrl.toString());

            // 存储本地历史记录
            try {
              localStorage.setItem(
                historyKey,
                JSON.stringify({
                  routeIndex: rIdx,
                  episodeIndex: epIdx,
                  episodeName: ep ? ep.name : `第${epIdx + 1}话`,
                  currentTime: 0,
                  updatedAt: Date.now(),
                })
              );
            } catch {}

            // 云端观看历史同步（若已登录）
            const token = localStorage.getItem('Bllii_token');
            if (token) {
              fetch('/api/user/history', {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                  Authorization: `Bearer ${token}`,
                },
                body: JSON.stringify({
                  video_id: video.id,
                  video_name: video.name,
                  picture: video.picture,
                  episode_name: ep ? ep.name : `第${epIdx + 1}话`,
                  route_index: rIdx,
                  episode_index: epIdx,
                  current_time: 0,
                  duration: 0,
                  progress: 0,
                }),
              }).catch(() => {});
            }
          },
          onTimeUpdate: (cur: number, dur: number, pct: number) => {
            if (cur >= 3) {
              try {
                localStorage.setItem(
                  'bllii_story_bookmark',
                  JSON.stringify({
                    videoId: video.id,
                    videoName: video.name,
                    episodeName:
                      video.play_groups?.[player.currentRouteIndex]?.episodes?.[
                        player.currentEpisodeIndex
                      ]?.name || `第${player.currentEpisodeIndex + 1}话`,
                    routeIndex: player.currentRouteIndex,
                    episodeIndex: player.currentEpisodeIndex,
                    currentTime: cur,
                    duration: Number.isFinite(dur) ? dur : 0,
                    updatedAt: Date.now(),
                  })
                );
                localStorage.setItem(
                  historyKey,
                  JSON.stringify({
                    episodeName:
                      player.episodes?.[player.currentEpisodeIndex]?.name || '',
                    routeIndex: player.currentRouteIndex,
                    episodeIndex: player.currentEpisodeIndex,
                    currentTime: cur,
                    duration: dur,
                    progress: pct,
                    updatedAt: Date.now(),
                  })
                );
              } catch {}
            }
          },
        });

        modernPlayerRef.current = player;
        player.loadVideoData(video, initRoute, initEp, resumeTime);

        // 一起看：本地播放态变化时推送状态；无控制权的成员由 handleWatchLiveEvent 回弹
        const vj = player.player;
        if (vj && typeof vj.on === 'function') {
          vj.on('play', () => handleWatchLiveEvent(vj, 'play'));
          vj.on('pause', () => handleWatchLiveEvent(vj, 'pause'));
          vj.on('seeked', () => handleWatchLiveEvent(vj, 'seeked'));
          // 媒体就绪后应用挂起的远端对齐（加入房间/切集时媒体可能尚未加载）
          vj.on('loadedmetadata', () => applyPendingSeek());
          vj.on('ratechange', () => {
            const watchClient = watchRef.current;
            if (!watchClient || !watchClient.isHost || watchClient.applyingRemote) return;
            void watchClient.pushState({
              rate:
                typeof vj.playbackRate === 'function' ? vj.playbackRate() || 1 : 1,
            });
          });
          syncWatchControls();
        }
      } catch (err) {
        console.error('初始化现代化播放器失败:', err);
      }
    };

    initPlayerEngine();

    return () => {
      isMounted = false;
      if (modernPlayerRef.current) {
        try {
          modernPlayerRef.current.destroy();
        } catch {}
        modernPlayerRef.current = null;
      }
    };
  }, [video?.id]);

  // 交互处理器
  const handleSelectEp = (epIdx: number) => {
    if (watchGuestLocked()) return;
    setSelectedEpIdx(epIdx);
    selectedEpIdxRef.current = epIdx;
    if (modernPlayerRef.current) {
      modernPlayerRef.current.playEpisode(
        modernPlayerRef.current.currentRouteIndex,
        epIdx
      );
    }
  };

  const handleSelectRoute = (rIdx: number) => {
    if (watchGuestLocked()) return;
    setSelectedGroupIdx(rIdx);
    setSelectedEpIdx(0);
    selectedGroupIdxRef.current = rIdx;
    selectedEpIdxRef.current = 0;
    if (modernPlayerRef.current) {
      modernPlayerRef.current.switchRoute(rIdx);
    }
  };

  const handlePrevEp = () => {
    if (watchGuestLocked()) return;
    if (modernPlayerRef.current) {
      modernPlayerRef.current.playPrevEpisode();
    }
  };

  const handleNextEp = () => {
    if (watchGuestLocked()) return;
    if (modernPlayerRef.current) {
      modernPlayerRef.current.playNextEpisode();
    }
  };

  const handleToggleFollow = async () => {
    if (!video) return;
    const user = getUser();
    if (!user) {
      window.location.href = `/login?redirect=${encodeURIComponent(
        window.location.pathname + window.location.search
      )}`;
      return;
    }
    const vid = Number(video.id);
    if (isFavorite) {
      await removeFavorite(vid);
      setIsFavorite(false);
    } else {
      await addFavorite({
        id: vid,
        name: video.name,
        picture: video.picture,
        remarks: video.remarks,
      });
      setIsFavorite(true);
    }
  };

  if (loading) {
    return (
      <Layout title="正在加载播放..." activeNav="番剧">
        <div className="py-24 text-center text-slate-400 text-sm">
          正在载入番剧信息与播放线路...
        </div>
      </Layout>
    );
  }

  if (!video) {
    return (
      <Layout title="未找到番剧" activeNav="番剧">
        <div className="py-24 text-center text-slate-400">
          <p>抱歉，未找到该番剧视频或已被下架。</p>
          <a
            href="/category"
            className="mt-4 inline-block text-blue-500 font-medium"
          >
            返回番剧库 →
          </a>
        </div>
      </Layout>
    );
  }

  const playGroups: PlayGroup[] = video.play_groups || [];
  const currentGroup =
    playGroups[selectedGroupIdx] ||
    playGroups[0] || { player_code: '', server: '', note: '', episodes: [] };
  const episodes: Episode[] = currentGroup.episodes || [];
  const currentEp = episodes[selectedEpIdx] || episodes[0] || {
    name: '第01话',
    url: '',
  };
  const epLabel = currentEp.name || `第${String(selectedEpIdx + 1).padStart(2, '0')}话`;

  // 一起看面板：入房后置顶到右栏首位，未入房时收在选集下方
  const watchActive = watchRef.current?.active === true;
  const watchPanel = watchRef.current && (
    <WatchTogetherPanel
      watch={watchRef.current}
      videoId={Number(video.id)}
      videoName={video.name}
      danmakuOn={watchDanmakuOn}
      onToggleDanmaku={toggleWatchDanmaku}
      currentGroupIndex={() => selectedGroupIdxRef.current}
      currentEpisodeIndex={() => selectedEpIdxRef.current}
      currentEpisodeName={() =>
        episodes[selectedEpIdx]?.name ||
        `第${String(selectedEpIdx + 1).padStart(2, '0')}话`
      }
    />
  );

  return (
    <Layout
      title={`正在播放：${video.name} - bllii 放映室`}
      activeNav="番剧"
      description={`${video.name} 在线全集高清播放：${video.remarks || ''} ${
        video.area || ''
      }`}
      image={video.picture}
    >
      <div
        className={`player-room max-w-[1360px] mx-auto px-4 sm:px-6 pt-4 pb-12 transition-colors duration-300 ${
          isFocusMode ? 'bg-slate-950/95 rounded-3xl -mx-2 px-6 my-2' : ''
        }`}
      >
        {/* 顶部标语与专注模式切换 */}
        <div className="player-room__heading mb-3 flex items-center justify-between">
          <div className="player-room__identity flex items-center gap-2 text-xs font-semibold text-slate-600">
            <img src="/brand/bllii-symbol.svg" width={22} height={22} alt="" />
            <span className={isFocusMode ? 'text-slate-300' : 'text-slate-600'}>
              bllii 放映室 / 好故事，现在开始
            </span>
          </div>
          <button
            type="button"
            onClick={() => setIsFocusMode(!isFocusMode)}
            className={`px-3 py-1.5 rounded-xl text-xs font-semibold flex items-center gap-1.5 transition-all cursor-pointer ${
              isFocusMode
                ? 'bg-amber-400 text-slate-900 shadow-md font-bold'
                : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
            }`}
            title="专注观看模式"
          >
            <BrandIcon name="moon" size={16} />
            <span>{isFocusMode ? '退出专注' : '专注观看'}</span>
          </button>
        </div>

        {/* 顶部面包屑 */}
        <div
          className={`flex items-center justify-between text-xs sm:text-sm mb-3 flex-wrap gap-2 ${
            isFocusMode ? 'text-slate-400' : 'text-slate-500'
          }`}
        >
          <div className="flex items-center gap-1.5 flex-wrap">
            <a href="/" className="hover:text-blue-500 transition-colors">
              首页
            </a>
            <span>/</span>
            <a href="/category" className="hover:text-blue-500 transition-colors">
              {video.type_name || '番剧'}
            </a>
            <span>/</span>
            <span
              className={`font-semibold ${
                isFocusMode ? 'text-slate-200' : 'text-slate-800'
              }`}
            >
              {video.name}
            </span>
            <span>/</span>
            <span className="text-blue-600 font-bold">{epLabel}</span>
          </div>

          <div className="flex items-center gap-3 text-xs">
            <a
              href="#section-archive"
              className="hover:text-blue-500 transition-colors flex items-center gap-1 font-medium"
            >
              <span>作品档案与详情</span>
              <BrandIcon name="chevron-down" size={14} />
            </a>
          </div>
        </div>

        {/* 核心播放大厅：左侧 16:9 现代化播放器 + 右侧线路选集 */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* 左侧：播放器舞台与操作栏 */}
          <div className="lg:col-span-8 xl:col-span-9 flex flex-col gap-4">
            <div
              className={`player-stage relative w-full aspect-[16/9] bg-black overflow-hidden rounded-2xl shadow-xl transition-all ${
                isFocusMode ? 'ring-4 ring-blue-500/30 shadow-2xl' : ''
              }`}
              ref={playerContainerRef}
            >
              <div
                className="w-full h-full"
                dangerouslySetInnerHTML={{
                  __html:
                    '<video-js id="vplayer-element" class="video-js vjs-big-play-centered vjs-fill"></video-js>',
                }}
              />
              {/* 一起看聊天实时弹幕层（纯展示，不遮挡播放器交互） */}
              <WatchDanmakuOverlay
                ref={watchDanmakuRef}
                enabled={watchDanmakuOn}
              />
            </div>

            {/* 播放器下方：影片标题与操作条 */}
            <div
              className={`rounded-2xl p-4 sm:p-5 shadow-sm border flex flex-col sm:flex-row sm:items-center justify-between gap-4 transition-colors ${
                isFocusMode
                  ? 'bg-slate-900 border-slate-800 text-slate-100'
                  : 'bg-white border-slate-100 text-slate-800'
              }`}
            >
              <div>
                <div className="flex items-center gap-2.5 flex-wrap">
                  <h1 className="text-xl sm:text-2xl font-bold tracking-tight">
                    {video.name}
                  </h1>
                  <span className="text-base sm:text-lg font-bold text-blue-600">
                    {epLabel}
                  </span>
                </div>
                <p
                  className={`text-xs sm:text-sm mt-1.5 flex items-center gap-2 flex-wrap ${
                    isFocusMode ? 'text-slate-400' : 'text-slate-500'
                  }`}
                >
                  {[video.year, video.area, video.remarks]
                    .filter(Boolean)
                    .map((item, idx) => (
                      <React.Fragment key={idx}>
                        <span>{item}</span>
                        <span>•</span>
                      </React.Fragment>
                    ))}
                  <span className="px-2 py-0.5 rounded-full text-xs font-semibold bg-blue-50 text-blue-600">
                    {video.type_name || '番剧'}
                  </span>
                </p>
              </div>

              {/* 交互按钮组 */}
              <div className="flex items-center gap-2 shrink-0 flex-wrap">
                {/* 故事口袋收藏 */}
                <button
                  type="button"
                  data-pocket-id={video.id}
                  data-pocket-name={video.name}
                  data-pocket-picture={video.picture}
                  className="p-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-700 transition-all cursor-pointer"
                  title="放进故事口袋"
                  aria-label="放进故事口袋"
                >
                  <BrandIcon name="bookmark" size={18} />
                </button>

                {/* 上一集 */}
                <button
                  type="button"
                  onClick={handlePrevEp}
                  disabled={selectedEpIdx <= 0}
                  className="px-3 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs sm:text-sm font-semibold transition-all flex items-center gap-1.5 cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
                  title="上一集 (快捷键: [ )"
                >
                  <BrandIcon name="prev" size={16} />
                  <span>上一集</span>
                </button>

                {/* 下一集 */}
                <button
                  type="button"
                  onClick={handleNextEp}
                  disabled={selectedEpIdx >= episodes.length - 1}
                  className="px-3 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs sm:text-sm font-semibold transition-all flex items-center gap-1.5 cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
                  title="下一集 (快捷键: ] )"
                >
                  <span>下一集</span>
                  <BrandIcon name="next" size={16} />
                </button>

                {/* 追番按钮 */}
                <button
                  type="button"
                  onClick={handleToggleFollow}
                  className={`px-3.5 py-2 rounded-xl text-xs sm:text-sm font-bold transition-all flex items-center gap-1.5 cursor-pointer ${
                    isFavorite
                      ? 'bg-emerald-50 text-emerald-600 hover:bg-emerald-100'
                      : 'bg-blue-50 text-blue-600 hover:bg-blue-100'
                  }`}
                >
                  <BrandIcon
                    name={isFavorite ? 'check' : 'plus'}
                    size={16}
                  />
                  <span>{isFavorite ? '已追番' : '+ 追番'}</span>
                </button>

                {/* 番剧百科链接 */}
                <a
                  href={`/anime/${video.id}`}
                  className="px-3.5 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs sm:text-sm font-semibold transition-colors flex items-center gap-1"
                >
                  <span>番剧详情</span>
                </a>
              </div>
            </div>
          </div>

          {/* 右侧：一起看（入房时置顶）+ 播放节点与选集控制面板 */}
          <div className="lg:col-span-4 xl:col-span-3 flex flex-col gap-4">
            {watchActive && watchPanel}

            {/* 播放线路 */}
            {playGroups.length > 1 && (
              <div
                className={`rounded-2xl p-4 shadow-sm border transition-colors ${
                  isFocusMode
                    ? 'bg-slate-900 border-slate-800'
                    : 'bg-white border-slate-100'
                }`}
              >
                <h3
                  className={`text-xs font-bold uppercase tracking-wider mb-2.5 ${
                    isFocusMode ? 'text-slate-400' : 'text-slate-500'
                  }`}
                >
                  播放节点切换
                </h3>
                <div className="flex items-center gap-2 flex-wrap">
                  {playGroups.map((group, idx) => {
                    let routeLabel =
                      group.source_name ||
                      (group.server && group.server !== 'no'
                        ? group.server
                        : `节点 ${idx + 1}`);
                    return (
                      <button
                        key={idx}
                        type="button"
                        onClick={() => handleSelectRoute(idx)}
                        className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer ${
                          selectedGroupIdx === idx
                            ? 'bg-[#3f6fd8] text-white shadow-sm shadow-blue-500/30'
                            : isFocusMode
                            ? 'bg-slate-800 text-slate-300 hover:bg-slate-700'
                            : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                        }`}
                      >
                        {routeLabel}
                      </button>
                    );
                  })}
                </div>
              </div>
            )}

            {/* 选集列表 */}
            <div
              className={`rounded-2xl p-4 shadow-sm border flex-1 flex flex-col transition-colors ${
                isFocusMode
                  ? 'bg-slate-900 border-slate-800'
                  : 'bg-white border-slate-100'
              }`}
            >
              <div className="flex items-center justify-between mb-3">
                <h3
                  className={`text-sm font-bold ${
                    isFocusMode ? 'text-slate-200' : 'text-slate-800'
                  }`}
                >
                  选集列表{' '}
                  <span className="text-xs font-normal text-slate-400">
                    ({episodes.length}话)
                  </span>
                </h3>
                <span className="text-xs text-blue-600 font-semibold bg-blue-50 px-2 py-0.5 rounded-full">
                  自动连播已开启
                </span>
              </div>

              {/* 集数方块网格 */}
              <div className="grid grid-cols-4 sm:grid-cols-6 lg:grid-cols-4 gap-2 overflow-y-auto max-h-[380px] p-1 pr-1.5 scrollbar-thin">
                {episodes.map((ep, eIdx) => {
                  const epNum =
                    ep.name && ep.name.length <= 4
                      ? ep.name
                      : String(eIdx + 1).padStart(2, '0');
                  const isCurrent = selectedEpIdx === eIdx;
                  return (
                    <button
                      key={eIdx}
                      type="button"
                      onClick={() => handleSelectEp(eIdx)}
                      className={`h-10 rounded-xl text-xs font-bold transition-all flex items-center justify-center cursor-pointer truncate px-1 ${
                        isCurrent
                          ? 'bg-[#3f6fd8] text-white shadow-sm shadow-blue-500/30 ring-2 ring-blue-400/50'
                          : isFocusMode
                          ? 'bg-slate-800 text-slate-300 hover:bg-slate-700 hover:text-white'
                          : 'bg-slate-100 text-slate-700 hover:bg-slate-200 hover:text-blue-600'
                      }`}
                      title={ep.name}
                    >
                      {epNum}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* 一起看：建房 / 加入房间（未入房时收在选集下方） */}
            {!watchActive && watchPanel}
          </div>
        </div>

        {/* 下半部分：作品全景档案与深度简介 */}
        <div
          id="section-archive"
          className="mt-12 pt-8 border-t border-slate-200/80 scroll-mt-20"
        >
          <div className="bg-white rounded-3xl p-6 sm:p-8 shadow-sm border border-slate-100 flex flex-col md:flex-row items-start gap-6 sm:gap-8 mb-8">
            <div className="w-36 sm:w-44 shrink-0 aspect-[3/4.2] rounded-2xl overflow-hidden shadow-lg ring-2 ring-slate-100 bg-slate-100">
              <img
                src={video.picture || '/brand/bllii-app-blue.svg'}
                alt={video.name}
                className="w-full h-full object-cover"
                onError={(e) => {
                  const t = e.currentTarget;
                  t.onerror = null;
                  t.src = '/brand/bllii-app-blue.svg';
                }}
              />
            </div>

            <div className="flex-1 space-y-3.5">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-[#3f6fd8] text-white">
                  {video.type_name || '番剧'}
                </span>
                {video.remarks && (
                  <span className="px-2.5 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-600">
                    {video.remarks}
                  </span>
                )}
              </div>

              <div>
                <h2 className="text-2xl font-bold text-slate-800 tracking-tight">
                  {video.name}
                </h2>
                {video.sub_name && (
                  <p className="text-xs text-slate-400 mt-0.5">{video.sub_name}</p>
                )}
              </div>

              <p className="text-xs sm:text-sm text-slate-500 font-medium">
                {[video.year, video.area, video.language]
                  .filter(Boolean)
                  .join(' · ')}
              </p>

              {/* 剧情简介 */}
              <div className="pt-2">
                <h3 className="text-xs font-bold text-slate-700 uppercase mb-1.5">
                  剧情简介
                </h3>
                <div
                  className={`text-xs sm:text-sm text-slate-600 leading-relaxed transition-all ${
                    synopsisExpanded ? '' : 'line-clamp-3'
                  }`}
                >
                  {video.content
                    ? video.content.replace(/<[^>]+>/g, '')
                    : '暂无详细剧情简介。'}
                </div>
                {video.content && video.content.length > 120 && (
                  <button
                    type="button"
                    onClick={() => setSynopsisExpanded(!synopsisExpanded)}
                    className="text-xs text-blue-600 font-semibold mt-1 hover:underline cursor-pointer"
                  >
                    {synopsisExpanded ? '收起简介 ▲' : '展开全文 ▼'}
                  </button>
                )}
              </div>
            </div>
          </div>

          {/* 相关推荐 */}
          {related.length > 0 && (
            <div className="mb-8">
              <div className="section-heading mb-4">
                <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
                  <span>同好推荐</span>
                  <span className="text-blue-500 font-normal">›</span>
                </h2>
              </div>
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
                {related.slice(0, 10).map((item) => (
                  <VideoCard key={item.id} video={item} />
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </Layout>
  );
}
