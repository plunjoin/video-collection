import { getToken, clearSession } from './auth';
export async function growthRequest(path: string, body?: unknown) {
  const token = getToken();
  if (!token) throw new Error('请先登录');
  const r = await fetch(path, { method: body === undefined ? 'GET' : 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const data = await r.json();
  if (r.status === 401) { clearSession(); throw new Error('登录已过期，请重新登录'); }
  if (!r.ok || data.code !== 1) throw new Error(data.error || data.msg || '操作失败');
  return data;
}
