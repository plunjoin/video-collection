import React, { useEffect, useState } from 'react';
import Layout from '../layouts/Layout';
import { getToken } from '../lib/auth';
import { deleteNotification, listNotifications, markNotificationsRead, notificationLink, type NotificationItem } from '../lib/notifications';

export default function NotificationsPage() {
  const [items, setItems] = useState<NotificationItem[]>([]);
  const [total, setTotal] = useState(0);
  const [unread, setUnread] = useState(0);
  const [unreadOnly, setUnreadOnly] = useState(false);
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);
  const [signedIn, setSignedIn] = useState(Boolean(getToken()));

  const load = async (reset: boolean, only: boolean) => {
    if (!getToken()) return;
    const nextPage = reset ? 1 : Math.floor(items.length / 20) + 1;
    setBusy(true);
    setStatus('');
    try {
      const result = await listNotifications(nextPage, only);
      setItems((prev) => (reset ? result.data : [...prev, ...result.data]));
      setTotal(result.total);
      setUnread(result.unread_count);
      window.dispatchEvent(new Event('notifications-changed'));
    } catch (error) {
      setStatus(error instanceof Error ? error.message : '消息加载失败');
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    setSignedIn(Boolean(getToken()));
    void load(true, unreadOnly);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [unreadOnly]);

  const markOne = async (id: number) => {
    try {
      await markNotificationsRead([id]);
      await load(true, unreadOnly);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : '操作失败');
    }
  };

  const remove = async (id: number) => {
    try {
      await deleteNotification(id);
      await load(true, unreadOnly);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : '删除失败');
    }
  };

  const markAll = async () => {
    setBusy(true);
    try {
      await markNotificationsRead();
      await load(true, unreadOnly);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : '操作失败');
    } finally {
      setBusy(false);
    }
  };

  const open = async (item: NotificationItem) => {
    const link = notificationLink(item);
    if (!link) return;
    if (!item.is_read) {
      try { await markNotificationsRead([item.id]); } catch { /* Navigation still works. */ }
    }
    window.location.href = link;
  };

  const loaded = items.length;

  return (
    <Layout title="消息通知 - bllii">
      <div className="inbox">
        <header className="inbox__header">
          <h1>消息通知 <span>{unread ? `(${unread} 未读)` : ''}</span></h1>
          {!signedIn || unread === 0 ? null : (
            <button type="button" onClick={markAll} disabled={busy}>全部标为已读</button>
          )}
        </header>
        <div className="inbox__tabs" role="group" aria-label="消息筛选">
          <button type="button" data-filter="all" aria-pressed={!unreadOnly} onClick={() => setUnreadOnly(false)}>全部</button>
          <button type="button" data-filter="unread" aria-pressed={unreadOnly} onClick={() => setUnreadOnly(true)}>未读</button>
        </div>
        <p className="inbox__status" role="status">{status}</p>

        <div className="inbox__list">
          {!signedIn ? (
            <div className="inbox__empty">
              <img src="/brand/bllii-symbol.svg" alt="" />
              <h2>登录后查看消息</h2>
              <a href="/login?redirect=/notifications">去登录</a>
            </div>
          ) : total === 0 && loaded === 0 && !busy ? (
            <div className="inbox__empty">
              <img src="/brand/bllii-symbol.svg" alt="" />
              <h2>{unreadOnly ? '没有未读消息' : '暂无消息'}</h2>
            </div>
          ) : (
            items.map((item) => (
              <article key={item.id} className={`inbox__item${item.is_read ? '' : ' is-unread'}`}>
                <div className="inbox__content">
                  <strong>{item.title || '消息通知'}</strong>
                  {item.content ? <p>{item.content}</p> : null}
                  <time>{Number.isNaN(new Date(item.created_at).getTime()) ? '' : new Date(item.created_at).toLocaleString('zh-CN')}</time>
                </div>
                <div className="inbox__actions">
                  {notificationLink(item) ? (
                    <a href={notificationLink(item) || '#'} onClick={(event) => { event.preventDefault(); void open(item); }}>查看</a>
                  ) : null}
                  {!item.is_read ? (
                    <button type="button" onClick={() => markOne(item.id)}>标为已读</button>
                  ) : null}
                  <button type="button" onClick={() => remove(item.id)}>删除</button>
                </div>
              </article>
            ))
          )}
        </div>

        {signedIn && loaded < total ? (
          <button className="inbox__more" type="button" disabled={busy} onClick={() => load(false, unreadOnly)}>加载更多</button>
        ) : null}
      </div>
    </Layout>
  );
}
