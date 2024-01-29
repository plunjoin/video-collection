// 用户身份鉴权与同步客户端 (直连 video-collection-api /api/login, /api/register, /api/me)

export interface User {
  id: number;
  username: string;
  nickname: string;
  role: string;
  avatar?: string;
  decorations?: { avatar: string; frame: string; badge: string; nickname_color: string };
  wallet?: { balance: number };
}

export interface AuthResponse {
  code: number;
  msg?: string;
  error?: string;
  token?: string;
  user?: User;
}

export interface FavoriteItem {
  id: number;
  user_id: number;
  video_id: number;
  video_name: string;
  picture: string;
  remarks: string;
  created_at: string;
}

export interface HistoryItem {
  id: number;
  user_id: number;
  video_id: number;
  video_name: string;
  picture: string;
  episode_name: string;
  route_index: number;
  episode_index?: number;
  current_time?: number;
  progress: number;
  duration: number;
  created_at: string;
}

const TOKEN_KEY = 'Bllii_token';
const USER_KEY = 'Bllii_user';

export function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function getUser(): User | null {
  if (typeof window === 'undefined') return null;
  const raw = localStorage.getItem(USER_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as User;
  } catch {
    return null;
  }
}

export function setSession(token: string, user: User) {
  if (typeof window === 'undefined') return;
  localStorage.setItem(TOKEN_KEY, token);
  localStorage.setItem(USER_KEY, JSON.stringify(user));
  document.cookie = `auth_token=${token}; path=/; max-age=2592000; SameSite=Lax`;
  window.dispatchEvent(new CustomEvent('auth-changed', { detail: { loggedIn: true, user } }));
}

export function clearSession() {
  if (typeof window === 'undefined') return;
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
  document.cookie = `auth_token=; path=/; max-age=0; SameSite=Lax`;
  window.dispatchEvent(new CustomEvent('auth-changed', { detail: { loggedIn: false, user: null } }));
}

export async function login(username: string, password: string): Promise<AuthResponse> {
  try {
    const res = await fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });
    const data = await res.json();
    if (data.code === 1 && data.token && data.user) {
      setSession(data.token, data.user);
    }
    return data;
  } catch (e: any) {
    return { code: 0, error: e.message || '网络连接超时，请重试' };
  }
}

export async function register(username: string, password: string, nickname?: string): Promise<AuthResponse> {
  try {
    const res = await fetch('/api/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username,
        password,
        nickname: nickname || username
      })
    });
    const data = await res.json();
    if (data.code === 1 && data.token && data.user) {
      setSession(data.token, data.user);
    }
    return data;
  } catch (e: any) {
    return { code: 0, error: e.message || '网络连接超时，请重试' };
  }
}

export async function logout(): Promise<void> {
  try {
    const token = getToken();
    await fetch('/api/logout', {
      method: 'POST',
      headers: token ? { 'Authorization': `Bearer ${token}` } : {}
    });
  } catch {
    // 忽略登出请求网络报错
  } finally {
    clearSession();
  }
}

export async function checkMe(): Promise<User | null> {
  const token = getToken();
  if (!token) return null;
  try {
    const res = await fetch('/api/me', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) {
      clearSession();
      return null;
    }
    const data = await res.json();
    if (data.code === 1 && data.data) {
      const u: User = {
        id: data.data.id,
        username: data.data.username,
        nickname: data.data.nickname || data.data.username,
        role: data.data.role,
        avatar: data.data.avatar,
        decorations: data.data.decorations,
        wallet: data.data.wallet
      };
      localStorage.setItem(USER_KEY, JSON.stringify(u));
      return u;
    }
    clearSession();
    return null;
  } catch {
    return getUser();
  }
}

// 追番收藏列表
export async function getFavorites(): Promise<FavoriteItem[]> {
  const token = getToken();
  if (!token) return [];
  try {
    const res = await fetch('/api/user/favorites', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    if (data.code === 1 && Array.isArray(data.data)) {
      return data.data;
    }
    return [];
  } catch {
    return [];
  }
}

// 添加追番
export async function addFavorite(video: { id: number; name: string; picture: string; remarks?: string }): Promise<boolean> {
  const token = getToken();
  if (!token) return false;
  try {
    const res = await fetch('/api/user/favorites', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        video_id: video.id,
        video_name: video.name,
        picture: video.picture,
        remarks: video.remarks || '更新中'
      })
    });
    const data = await res.json();
    return data.code === 1;
  } catch {
    return false;
  }
}

// 取消追番
export async function removeFavorite(videoId: number): Promise<boolean> {
  const token = getToken();
  if (!token) return false;
  try {
    const res = await fetch(`/api/user/favorites?video_id=${videoId}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    return data.code === 1;
  } catch {
    return false;
  }
}

// 播放历史列表
export async function getHistory(): Promise<HistoryItem[]> {
  const token = getToken();
  if (!token) return [];
  try {
    const res = await fetch('/api/user/history', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    if (data.code === 1 && Array.isArray(data.data)) {
      return data.data;
    }
    return [];
  } catch {
    return [];
  }
}
