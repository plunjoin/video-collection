// 用户身份鉴权与同步客户端 (直连 video-collection-service /api/login, /api/register, /api/me)

export interface User {
  id: number;
  username: string;
  nickname: string;
  role: string;
  avatar?: string;
  /** 用户自己填写的头像；avatar 可能是已佩戴的装扮头像。 */
  profileAvatar?: string;
  bio?: string;
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

// 资料保存后刷新本地缓存的用户信息，并通知导航栏重新渲染。
export function updateStoredUser(user: User) {
  if (typeof window === 'undefined') return;
  localStorage.setItem(USER_KEY, JSON.stringify(user));
  window.dispatchEvent(new CustomEvent('auth-changed', { detail: { loggedIn: true, user } }));
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
        profileAvatar: data.data.profile_avatar,
        bio: data.data.bio,
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

// 修改个人资料（昵称 / 头像 / 简介）
export async function updateProfile(payload: {
  nickname: string;
  avatar: string;
  bio: string;
}): Promise<AuthResponse> {
  const token = getToken();
  if (!token) return { code: 0, error: '请先登录' };
  try {
    const res = await fetch('/api/me', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify(payload)
    });
    const data = await res.json();
    if (data.code === 1 && data.data) {
      const current = getUser();
      const mapped: User = {
        id: data.data.id,
        username: data.data.username,
        nickname: data.data.nickname || data.data.username,
        role: data.data.role,
        avatar: data.data.avatar,
        profileAvatar: data.data.profile_avatar,
        bio: data.data.bio,
        decorations: data.data.decorations ?? current?.decorations,
        wallet: data.data.wallet ?? current?.wallet
      };
      updateStoredUser(mapped);
      return { ...data, user: mapped };
    }
    return data;
  } catch (e: any) {
    return { code: 0, error: e.message || '网络连接超时，请重试' };
  }
}

// 修改密码（成功后服务端会吊销其他设备的登录态）
export async function changePassword(
  oldPassword: string,
  newPassword: string
): Promise<AuthResponse & { revoked_sessions?: number }> {
  const token = getToken();
  if (!token) return { code: 0, error: '请先登录' };
  try {
    const res = await fetch('/api/me/password', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({ old_password: oldPassword, new_password: newPassword })
    });
    return await res.json();
  } catch (e: any) {
    return { code: 0, error: e.message || '网络连接超时，请重试' };
  }
}

export interface LoginSession {
  id: string;
  current: boolean;
  ip: string;
  user_agent: string;
  created_at: string;
  expires_at: string;
}

// 当前账号的登录设备
export async function getSessions(): Promise<LoginSession[]> {
  const token = getToken();
  if (!token) return [];
  try {
    const res = await fetch('/api/me/sessions', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    return data.code === 1 && Array.isArray(data.data) ? data.data : [];
  } catch {
    return [];
  }
}

// 下线指定设备
export async function revokeSession(id: string): Promise<boolean> {
  const token = getToken();
  if (!token) return false;
  try {
    const res = await fetch(`/api/me/sessions?id=${encodeURIComponent(id)}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    return data.code === 1;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// 账号中心：邮箱 / 手机绑定、验证码找回密码、头像上传、注销账号
// ---------------------------------------------------------------------------

export interface UserContact {
  email: string;
  email_verified: boolean;
  phone: string;
  phone_verified: boolean;
}

export type ContactChannel = 'email' | 'phone';

interface ApiResult {
  code: number;
  msg?: string;
  error?: string;
}

async function authedPost(path: string, body: unknown): Promise<ApiResult> {
  const token = getToken();
  if (!token) return { code: 0, error: '请先登录' };
  try {
    const res = await fetch(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(body)
    });
    return await res.json();
  } catch (e: any) {
    return { code: 0, error: e.message || '网络连接超时，请重试' };
  }
}

// 当前账号绑定的邮箱 / 手机
export async function getContact(): Promise<UserContact | null> {
  const token = getToken();
  if (!token) return null;
  try {
    const res = await fetch('/api/me/contact', { headers: { Authorization: `Bearer ${token}` } });
    const data = await res.json();
    return data.code === 1 && data.data ? data.data : null;
  } catch {
    return null;
  }
}

// 发送验证码。purpose=reset 无需登录；purpose=bind 需要登录。
export async function sendCode(
  channel: ContactChannel,
  target: string,
  purpose: 'reset' | 'bind'
): Promise<ApiResult & { dev_code?: string; expires_in?: number }> {
  try {
    const token = getToken();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetch('/api/auth/send-code', {
      method: 'POST',
      headers,
      body: JSON.stringify({ channel, target, purpose })
    });
    return await res.json();
  } catch (e: any) {
    return { code: 0, error: e.message || '网络连接超时，请重试' };
  }
}

export function bindContact(channel: ContactChannel, target: string, code: string) {
  return authedPost('/api/me/contact/bind', { channel, target, code });
}

export function unbindContact(channel: ContactChannel, password: string) {
  return authedPost('/api/me/contact/unbind', { channel, password });
}

export function resetPassword(
  channel: ContactChannel,
  target: string,
  code: string,
  newPassword: string
): Promise<ApiResult & { revoked_sessions?: number }> {
  return authedPost('/api/auth/reset-password', {
    channel,
    target,
    code,
    new_password: newPassword
  }) as Promise<ApiResult & { revoked_sessions?: number }>;
}

export function deleteAccount(password: string): Promise<ApiResult> {
  return authedPost('/api/me/delete', { password });
}

// 上传头像：成功时返回可直接写入资料的相对路径。
export async function uploadAvatar(file: File): Promise<ApiResult & { url?: string }> {
  const token = getToken();
  if (!token) return { code: 0, error: '请先登录' };
  const form = new FormData();
  form.append('file', file);
  try {
    const res = await fetch('/api/me/avatar', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: form
    });
    return await res.json();
  } catch (e: any) {
    return { code: 0, error: e.message || '网络连接超时，请重试' };
  }
}

export interface AvatarHistoryItem {
  id: number;
  url: string;
  /** 上传时使用的存储类型：local / s3 */
  provider: string;
  created_at: string;
  /** 是否为当前正在使用的头像 */
  current: boolean;
}

// 历史头像列表：最多保留 20 条，最新的在前。
export async function listAvatars(): Promise<AvatarHistoryItem[]> {
  const token = getToken();
  if (!token) return [];
  try {
    const res = await fetch('/api/me/avatars', { headers: { Authorization: `Bearer ${token}` } });
    const data = await res.json();
    return data.code === 1 && Array.isArray(data.data) ? data.data : [];
  } catch {
    return [];
  }
}

// 把某个历史头像切回当前头像（立即生效，无需再保存资料）。
export function useAvatar(id: number): Promise<ApiResult & { url?: string }> {
  return authedPost('/api/me/avatars/use', { id }) as Promise<ApiResult & { url?: string }>;
}

// 删除某条历史头像；服务端会同时删除对象存储 / 磁盘上的源文件。
export async function deleteAvatar(id: number): Promise<ApiResult> {
  const token = getToken();
  if (!token) return { code: 0, error: '请先登录' };
  try {
    const res = await fetch(`/api/me/avatars?id=${encodeURIComponent(String(id))}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` }
    });
    return await res.json();
  } catch (e: any) {
    return { code: 0, error: e.message || '网络连接超时，请重试' };
  }
}
