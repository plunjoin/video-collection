// 一起看（Watch Together）同步引擎。
// 与客户端一致的轮询模型：成员心跳拉取服务端推算的目标进度，房主操作后主动推送。

export interface WatchMemberView {
  user_id: number;
  nickname: string;
  avatar: string;
  position_ms: number;
  is_host: boolean;
}

export interface WatchMessageView {
  id: number;
  user_id: number;
  author_name: string;
  content: string;
  created_at: string;
}

export interface WatchSnapshot {
  code: string;
  video_id: number;
  group_index: number;
  episode_index: number;
  title: string;
  host_id: number;
  version: number;
  playing: boolean;
  position_ms: number;
  anchor_ms: number;
  target_position_ms: number;
  rate: number;
  viewer_is_host: boolean;
  control_mode: 'host' | 'all';
  server_time_ms: number;
  members: WatchMemberView[];
}

const FOLLOW_DRIFT_MS = 1500;
const HOST_CORRECT_MS = 2500;
const REMOTE_GUARD_MS = 2500;
// 漂移纠偏最小间隔：跟随房主真实位置（宁可有少许延迟），避免房主短暂缓冲时来回拽。
const CORRECTIVE_SEEK_COOLDOWN_MS = 3000;

export class WatchApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

async function watchFetch(path: string, body?: unknown, method = 'POST') {
  const token = localStorage.getItem('Bllii_token') || '';
  const res = await fetch(path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data: any = null;
  try {
    data = await res.json();
  } catch {}
  if (!res.ok || !data || data.code !== 1) {
    throw new WatchApiError(
      (data && (data.error || data.msg)) || '请求失败，请稍后重试',
      res.status
    );
  }
  return data;
}

export class WatchTogetherClient {
  snapshot: WatchSnapshot | null = null;
  messages: WatchMessageView[] = [];
  /** 最近一条提示（权限不足、掉线等），由面板展示。 */
  lastNotice = '';
  /** 当前用户 id：SSE 广播流不含 viewer_is_host，由本端按 host_id 判定。 */
  myUserId: number | null = null;

  private sinceMsgId = 0;
  private timer: number | null = null;
  private syncing = false;
  private misses = 0;
  private appliedVersion = 0;
  private lastPushedVersion = 0;
  private serverOffsetMs = 0;
  private authNotified = false;
  private lastCorrectiveSeekAt = 0;
  private es: EventSource | null = null;
  private sseConnected = false;
  private armedHost = false;
  private armedSse = false;
  /**
   * 待媒体加载完成后需对齐的进度（loadedmetadata 时由播放页消费）。
   * 媒体未就绪时 currentTime 赋值会被忽略，不挂起的话这次对齐会被"吃掉"。
   */
  pendingSeek: { ms: number; playing: boolean } | null = null;
  /** 应用远端状态期间抑制本地推送，避免同步循环。 */
  applyingRemote = false;
  private applyingRemoteTimer: number | null = null;

  // 播放器挂钩，由播放页注入
  getPositionMs: () => number = () => 0;
  isPlaying: () => boolean = () => false;
  getGroupIndex: () => number = () => 0;
  getEpisodeIndex: () => number = () => 0;
  applyRemote: (snap: WatchSnapshot) => void = () => {};
  onNotify: (message: string) => void = () => {};
  /** 新聊天消息到达（自己发送、SSE 推送、心跳增量），用于把消息送上实时弹幕。 */
  onChatArrived: (msg: WatchMessageView, own: boolean) => void = () => {};
  onChange: () => void = () => {};

  private listeners = new Set<() => void>();

  /** 订阅状态变化；返回取消订阅函数。替代早期对 onChange 的猴子补丁订阅。 */
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emitChange() {
    this.onChange();
    for (const listener of this.listeners) listener();
  }

  get active() {
    return this.snapshot !== null;
  }

  get code() {
    return this.snapshot?.code || '';
  }

  get isHost() {
    const snap = this.snapshot;
    if (!snap) return false;
    if (this.myUserId != null) return snap.host_id === this.myUserId;
    return snap.viewer_is_host === true;
  }

  /** 当前用户是否可以控制播放（房主，或房间开放了控制权）。 */
  get canControl() {
    const snap = this.snapshot;
    if (!snap) return false;
    return snap.viewer_is_host || snap.control_mode === 'all';
  }

  /** 成员可在客户端调用的提示入口。 */
  notify(message: string) {
    this.lastNotice = message;
    this.onNotify(message);
    this.emitChange();
  }

  get hostName() {
    const snap = this.snapshot;
    if (!snap) return '房主';
    const host = snap.members.find((m) => m.user_id === snap.host_id);
    return host?.nickname || '房主';
  }

  async create(
    videoId: number,
    groupIndex: number,
    episodeIndex: number,
    controlMode: 'host' | 'all' = 'host'
  ) {
    const request = (mode: string | null) =>
      watchFetch('/api/watch/rooms', {
        video_id: videoId,
        group_index: groupIndex,
        episode_index: episodeIndex,
        ...(mode ? { control_mode: mode } : {}),
      });
    try {
      this.activate((await request(controlMode === 'host' ? null : controlMode)).data);
    } catch (error) {
      // 旧服务端不认识 control_mode 字段（严格 JSON 解码返回 400），退回默认仅房主模式重试。
      if (error instanceof WatchApiError && error.status === 400 && controlMode !== 'host') {
        try {
          this.activate((await request(null)).data);
          this.notify('当前服务端版本较旧，已按仅房主控制创建房间');
          return;
        } catch (retryError) {
          throw retryError;
        }
      }
      throw error;
    }
  }

  async join(code: string) {
    const data = await watchFetch('/api/watch/rooms/join', {
      code: code.trim().toUpperCase(),
    });
    this.activate(data.data);
  }

  private activate(snapshot: WatchSnapshot) {
    this.snapshot = snapshot;
    this.appliedVersion = 0;
    this.lastPushedVersion = 0;
    this.authNotified = false;
    this.messages = [];
    this.sinceMsgId = 0;
    this.misses = 0;
    this.setPollMode();
    void this.tick();
    this.connectEvents();
    this.emitChange();
  }

  /** 心跳定时器：房主是广播源，2.5 秒上报真实进度；
   * 成员在 SSE 在线时 5 秒（保活 + 进度上报 + 漂移纠偏），回退轮询时 2 秒。 */
  private setPollMode() {
    this.stopLoop();
    this.armedHost = this.isHost;
    this.armedSse = this.sseConnected;
    const period = this.isHost
      ? 2500
      : this.sseConnected
      ? 5000
      : 2000;
    this.timer = window.setInterval(() => void this.tick(), period);
  }

  /** 房主身份或 SSE 连接状态变化后重排心跳周期。 */
  private ensurePollMode() {
    if (this.timer === null) return;
    if (this.armedHost !== this.isHost || this.armedSse !== this.sseConnected) {
      this.setPollMode();
    }
  }

  /** SSE 实时通道：状态/聊天/解散即时推送；失败时 EventSource 自动重连，期间回退轮询。 */
  private connectEvents() {
    if (this.es || !this.snapshot || this.myUserId == null) return;
    const token = localStorage.getItem('Bllii_token') || '';
    const es = new EventSource(
      `/api/watch/rooms/events?code=${encodeURIComponent(
        this.snapshot.code
      )}&token=${encodeURIComponent(token)}`
    );
    es.onopen = () => {
      if (!this.sseConnected) {
        this.sseConnected = true;
        this.setPollMode();
        this.emitChange();
      }
    };
    es.addEventListener('state', (e) => {
      try {
        const snap = JSON.parse((e as MessageEvent).data) as WatchSnapshot;
        if (!this.snapshot) return;
        this.absorb(snap);
        this.followRemote(snap);
        this.emitChange();
      } catch {}
    });
    es.addEventListener('chat', (e) => {
      try {
        const msg = JSON.parse((e as MessageEvent).data) as WatchMessageView;
        if (msg.id > this.sinceMsgId) {
          this.messages.push(msg);
          this.sinceMsgId = msg.id;
          this.onChatArrived(msg, false);
          this.emitChange();
        }
      } catch {}
    });
    es.addEventListener('closed', () => {
      this.notify('房间已解散');
      this.deactivate();
    });
    es.onerror = () => {
      // EventSource 原生自动重连；断开期间回退到 2 秒轮询。
      if (this.sseConnected) {
        this.sseConnected = false;
        this.setPollMode();
        this.emitChange();
      }
    };
    this.es = es;
  }

  private closeEvents() {
    if (this.es) {
      this.es.close();
      this.es = null;
    }
    this.sseConnected = false;
  }

  private stopLoop() {
    if (this.timer !== null) {
      window.clearInterval(this.timer);
      this.timer = null;
    }
  }

  private guardRemoteOps() {
    this.applyingRemote = true;
    if (this.applyingRemoteTimer !== null) {
      window.clearTimeout(this.applyingRemoteTimer);
    }
    this.applyingRemoteTimer = window.setTimeout(() => {
      this.applyingRemote = false;
      this.applyingRemoteTimer = null;
    }, REMOTE_GUARD_MS);
  }

  /** 房主推送播放状态；开放控制权（all）时任何成员的本地操作同样会推送。 */
  async pushState(patch: {
    playing?: boolean;
    position_ms?: number;
    group_index?: number;
    episode_index?: number;
    rate?: number;
  }) {
    if (!this.snapshot || !this.canControl || this.applyingRemote) return;
    try {
      const data = await watchFetch('/api/watch/rooms/state', {
        code: this.snapshot.code,
        ...patch,
      });
      this.absorb(data.data);
      this.lastPushedVersion = (data.data as WatchSnapshot).version;
    } catch (error) {
      if (error instanceof WatchApiError) this.onNotify(error.message);
    }
  }

  /** 房主切换播放控制权限（host / all）。 */
  async setControlMode(mode: 'host' | 'all') {
    if (!this.snapshot || !this.isHost) {
      this.notify('只有房主可以修改控制权限');
      return;
    }
    try {
      const data = await watchFetch('/api/watch/rooms/control', {
        code: this.snapshot.code,
        mode,
      });
      this.absorb(data.data);
    } catch (error) {
      if (error instanceof WatchApiError && error.status === 404) {
        this.notify('当前服务端版本较旧，请升级服务端后使用控制权切换');
        return;
      }
      if (error instanceof WatchApiError) this.notify(error.message);
    }
  }

  private async tick() {
    const snap = this.snapshot;
    if (!snap || this.syncing) return;
    this.syncing = true;
    try {
      const data = await watchFetch('/api/watch/rooms/heartbeat', {
        code: snap.code,
        position_ms: Math.round(this.getPositionMs()),
        since_msg_id: this.sinceMsgId,
      });
      this.misses = 0;
      const incoming = (data.data?.messages || []) as WatchMessageView[];
      for (const msg of incoming) {
        if (msg.id > this.sinceMsgId) {
          this.messages.push(msg);
          this.onChatArrived(msg, false);
        }
      }
      if (this.messages.length > 200) {
        this.messages.splice(0, this.messages.length - 200);
      }
      if (incoming.length > 0) {
        this.sinceMsgId = this.messages[this.messages.length - 1].id;
      }
      this.absorb(data.data as WatchSnapshot);
      if (this.snapshot?.viewer_is_host) {
        await this.hostCorrection();
      } else if (this.snapshot) {
        this.followRemote(this.snapshot);
      }
      this.emitChange();
    } catch (error) {
      if (error instanceof WatchApiError) {
        if (error.status === 404) {
          this.notify('房间已解散');
          this.deactivate();
        } else if (error.status === 401) {
          // 登录过期：明确告知，不再静默失联。
          if (!this.authNotified) {
            this.authNotified = true;
            this.notify('登录已过期，请重新登录后一起看');
          }
        } else {
          this.notify(error.message);
        }
      } else {
        this.misses += 1;
        if (this.misses === 3) this.notify('一起看连接不稳定…');
      }
    } finally {
      this.syncing = false;
    }
  }

  /** 成员跟随：版本变化（切集/播放态/房主主动操作）立即对齐；
   * 纯进度漂移的纠偏按冷却节流（跟随房主真实位置，宁可有延迟也不来回拽）。
   * 自己推送的版本不重复应用。 */
  private followRemote(snap: WatchSnapshot) {
    if (snap.version === this.lastPushedVersion) {
      this.appliedVersion = snap.version;
      return;
    }
    const episodeChanged =
      snap.group_index !== this.getGroupIndex() ||
      snap.episode_index !== this.getEpisodeIndex();
    const playStateChanged = snap.playing !== this.isPlaying();
    if (episodeChanged || snap.version !== this.appliedVersion || playStateChanged) {
      if (snap.version !== this.appliedVersion) this.appliedVersion = snap.version;
      this.guardRemoteOps();
      this.applyRemote(snap);
      return;
    }
    const drift = snap.target_position_ms - this.getPositionMs();
    if (Math.abs(drift) > FOLLOW_DRIFT_MS) {
      const now = Date.now();
      if (now - this.lastCorrectiveSeekAt < CORRECTIVE_SEEK_COOLDOWN_MS) return;
      this.lastCorrectiveSeekAt = now;
      this.guardRemoteOps();
      this.applyRemote(snap);
    }
  }

  /** 房主漂移校正：实际进度偏离锚点推算超 2.5 秒（缓冲、卡顿）时重推锚点。
   * 推算必须按房主倍速换算，否则倍速播放时每 2.5 秒都会误判漂移，
   * 造成持续升版本 → 成员被反复硬 seek。 */
  private async hostCorrection() {
    const snap = this.snapshot;
    if (!snap || !snap.playing || snap.anchor_ms <= 0) return;
    const serverNow = Date.now() + this.serverOffsetMs;
    const rate = snap.rate > 0 ? snap.rate : 1;
    const projected =
      snap.position_ms + Math.max(0, serverNow - snap.anchor_ms) * rate;
    const actual = Math.round(this.getPositionMs());
    if (Math.abs(projected - actual) > HOST_CORRECT_MS) {
      await this.pushState({ playing: this.isPlaying(), position_ms: actual });
    }
  }

  /** 吸收服务端快照：版本回退（HTTP 并发响应乱序）时拒绝旧状态，
   * 避免房主连发 pause→play 后旧位置把房间状态拽回去。 */
  private absorb(snap: WatchSnapshot) {
    if (snap.server_time_ms > 0) {
      this.serverOffsetMs = snap.server_time_ms - Date.now();
    }
    const cur = this.snapshot;
    if (
      cur &&
      snap.version < cur.version &&
      snap.anchor_ms <= cur.anchor_ms
    ) {
      return;
    }
    this.snapshot = snap;
    this.ensurePollMode();
    this.emitChange();
  }

  async chat(content: string) {
    if (!this.snapshot) return;
    const data = await watchFetch('/api/watch/rooms/chat', {
      code: this.snapshot.code,
      content,
    });
    const msg = data.data as WatchMessageView;
    if (msg && msg.id > this.sinceMsgId) {
      this.messages.push(msg);
      this.sinceMsgId = msg.id;
      this.onChatArrived(msg, true);
      this.emitChange();
    }
  }

  async transferHost(userId: number) {
    if (!this.snapshot) return;
    const data = await watchFetch('/api/watch/rooms/host', {
      code: this.snapshot.code,
      user_id: userId,
    });
    this.absorb(data.data);
  }

  async leave() {
    const snap = this.snapshot;
    this.deactivate();
    if (snap) {
      try {
        await watchFetch('/api/watch/rooms/leave', { code: snap.code });
      } catch {}
    }
  }

  private deactivate() {
    this.stopLoop();
    this.closeEvents();
    if (this.applyingRemoteTimer !== null) {
      window.clearTimeout(this.applyingRemoteTimer);
      this.applyingRemoteTimer = null;
    }
    this.applyingRemote = false;
    this.snapshot = null;
    this.messages = [];
    this.sinceMsgId = 0;
    this.appliedVersion = 0;
    this.lastPushedVersion = 0;
    this.pendingSeek = null;
    this.emitChange();
  }

  destroy() {
    const snap = this.snapshot;
    this.closeEvents();
    this.stopLoop();
    this.snapshot = null;
    if (snap) {
      void watchFetch('/api/watch/rooms/leave', { code: snap.code }).catch(
        () => {}
      );
    }
  }
}
