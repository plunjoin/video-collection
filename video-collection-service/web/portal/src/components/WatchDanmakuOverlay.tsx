import React, {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
} from 'react';

/** 一条待渲染的弹幕。 */
export interface DanmakuSpawn {
  /** 唯一 id（聊天消息 id），用于去重与 React key。 */
  id: number | string;
  /** 已格式化好的弹幕文本（如「昵称：内容」）。 */
  text: string;
  /** 弹幕颜色。 */
  color?: string;
}

interface ActiveDanmaku extends DanmakuSpawn {
  key: string;
  lane: number;
  /** 横穿整个舞台所需时长（秒）。 */
  duration: number;
}

const LANE_HEIGHT = 34;
const MAX_LANES = 6;
/** 弹幕穿过舞台的基础速度（px/s），与客户端滚动观感一致。 */
const ROLL_SPEED = 110;

export interface WatchDanmakuOverlayHandle {
  /** 推送一条弹幕；enabled=false 或同 id 重复时忽略。 */
  push: (spawn: DanmakuSpawn) => void;
}

/**
 * 一起看聊天实时弹幕层：消息从播放器右侧飘向左侧，与客户端观感一致。
 * 纯展示层（pointer-events: none），挂在播放器舞台内部。
 */
const WatchDanmakuOverlay = forwardRef<
  WatchDanmakuOverlayHandle,
  { enabled: boolean }
>(({ enabled }, ref) => {
  const [items, setItems] = useState<ActiveDanmaku[]>([]);
  const [stageSize, setStageSize] = useState({ width: 0, height: 0 });
  const seenIds = useRef(new Set<string>());
  /** 每条弹道最近一次占用时间，选道时优先挑空闲最久的。 */
  const laneLastUse = useRef<number[]>([]);
  const seq = useRef(0);
  const stageRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const el = stageRef.current;
    if (!el) return;
    const update = () => {
      setStageSize({ width: el.clientWidth, height: el.clientHeight });
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const push = useCallback(
    (spawn: DanmakuSpawn) => {
      if (!enabled) return;
      const key = String(spawn.id);
      if (seenIds.current.has(key)) return;
      seenIds.current.add(key);
      if (seenIds.current.size > 400) {
        seenIds.current = new Set(Array.from(seenIds.current).slice(-200));
      }

      const lanes = Math.min(
        MAX_LANES,
        Math.max(1, Math.floor(stageSize.height / LANE_HEIGHT) || 3)
      );
      const now = Date.now();
      let lane = 0;
      let oldest = Infinity;
      for (let i = 0; i < lanes; i++) {
        const used = laneLastUse.current[i] ?? 0;
        if (used < oldest) {
          oldest = used;
          lane = i;
        }
      }
      laneLastUse.current[lane] = now;

      // 距离 = 舞台宽 + 自身宽（用 320px 估算文本宽度），速度恒定。
      const travel = stageSize.width + 320;
      const duration = Math.max(6, Math.min(14, travel / ROLL_SPEED));
      const seqNo = ++seq.current;
      setItems((prev) => {
        const next = [
          ...prev,
          {
            ...spawn,
            key: `${key}#${seqNo}`,
            lane: lane % lanes,
            duration,
          },
        ];
        return next.slice(-24);
      });
    },
    [enabled, stageSize.height, stageSize.width]
  );

  useImperativeHandle(ref, () => ({ push }), [push]);

  return (
    <div
      ref={stageRef}
      className="pointer-events-none absolute inset-0 z-20 overflow-hidden"
      aria-hidden
    >
      {enabled &&
        items.map((item) => (
          <span
            key={item.key}
            className="absolute whitespace-nowrap will-change-transform"
            style={{
              top: item.lane * LANE_HEIGHT + 6,
              left: '100%',
              color: item.color || '#ffffff',
              fontSize: 14,
              fontWeight: 600,
              lineHeight: '22px',
              padding: '2px 6px',
              borderRadius: 8,
              background: 'rgba(7, 11, 22, 0.45)',
              textShadow: '0 1px 2px rgba(0,0,0,0.8)',
              ['--bllii-roll-end' as string]: `translateX(calc(-100% - ${
                stageSize.width || 800
              }px))`,
              animation: `bllii-danmaku-roll ${item.duration}s linear forwards`,
            }}
            onAnimationEnd={() => {
              setItems((prev) => prev.filter((i) => i.key !== item.key));
            }}
          >
            {item.text}
          </span>
        ))}
      <style>{`
        @keyframes bllii-danmaku-roll {
          from { transform: translateX(0); }
          to { transform: var(--bllii-roll-end, translateX(-120%)); }
        }
      `}</style>
    </div>
  );
});

WatchDanmakuOverlay.displayName = 'WatchDanmakuOverlay';
export default WatchDanmakuOverlay;
