// 评论控件：从旧 Comments.astro 的脚本原样提取，改为显式挂载。
// 依赖 DOM 骨架（components/Comments.tsx 渲染）已存在于页面中；
// 调用方在挂载后动态 import 本模块即可（幂等：多次调用只生效一次）。
import { iconMarkup } from './brand-icons';
import { createComment, deleteComment, getComment, listComments, setCommentLike, GOD_COMMENT_LIKES, type CommentItem, type CommentTarget, type CommentSort } from './comments';
import { getToken, getUser } from './auth';
import { confirmAction } from './dialogs';
import { applyMemberAvatar, createMemberName } from './members';

let mounted = false;

export function mountComments(): void {
  if (mounted) return;
  const section = document.querySelector<HTMLElement>('[data-comment-target]');
  if (!section) return;
  mounted = true;

  const targetType = section.dataset.commentTarget as CommentTarget;
  const targetId = Number(section.dataset.targetId);
  const list = section.querySelector<HTMLElement>('[data-list]')!;
  const spotlight = section.querySelector<HTMLElement>('[data-spotlight]')!;
  const more = section.querySelector<HTMLButtonElement>('[data-more]')!;
  const input = section.querySelector<HTMLTextAreaElement>('[data-content]')!;
  const submit = section.querySelector<HTMLButtonElement>('[data-submit]')!;
  const message = section.querySelector<HTMLElement>('[data-message]')!;
  const externalMessage = section.querySelector<HTMLElement>('[data-external-message]')!;
  const identity = section.querySelector<HTMLElement>('[data-identity-name]')!;
  const avatar = section.querySelector<HTMLImageElement>('[data-avatar]')!;
  const login = section.querySelector<HTMLAnchorElement>('[data-login]')!;
  const fields = section.querySelector<HTMLElement>('[data-compose-fields]')!;
  const count = section.querySelector<HTMLElement>('[data-count]')!;
  let page = 0;
  let loaded = 0;
  let total = 0;
  let sort: CommentSort = 'latest';

  function el<K extends keyof HTMLElementTagNameMap>(tag: K, className = '', value = ''): HTMLElementTagNameMap[K] {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (value) node.textContent = value;
    return node;
  }

  function setMessage(value: string, error = false) {
    message.textContent = value;
    message.classList.toggle('is-error', error);
    externalMessage.textContent = value;
    externalMessage.classList.toggle('is-error', error);
    externalMessage.hidden = !value || !fields.hidden;
  }

  function announceChange(delta: number) {
    window.dispatchEvent(new CustomEvent('comments-changed', { detail: { targetType, targetId, delta } }));
  }

  function requireLogin(): boolean {
    if (getToken()) return true;
    window.location.href = `/login?redirect=${encodeURIComponent(location.pathname + location.search + '#comments')}`;
    return false;
  }

  function updateIdentity() {
    const user = getUser();
    const signedIn = Boolean(getToken() && user);
    const member = signedIn ? {name:user!.nickname || user!.username, avatar:user!.avatar, frame:user!.decorations?.frame, badge:user!.decorations?.badge, color:user!.decorations?.nickname_color} : {};
    if (signedIn) identity.replaceChildren(createMemberName(member), el('small','','，来说点什么吧'));
    else identity.textContent = '登录后即可评论';
    applyMemberAvatar(avatar, member);
    login.href = `/login?redirect=${encodeURIComponent(location.pathname + location.search + '#comments')}`;
    login.hidden = signedIn;
    fields.hidden = !signedIn;
    externalMessage.hidden = signedIn || !externalMessage.textContent;
  }

  function dateLabel(value: string): string {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? '' : date.toLocaleString('zh-CN', { dateStyle: 'medium', timeStyle: 'short' });
  }

  function action(name: string, label: string, comment: CommentItem): HTMLButtonElement {
    const button = el('button', 'discussion__action', label);
    button.type = 'button';
    button.dataset.action = name;
    button.dataset.id = String(comment.id);
    button.dataset.root = String(comment.root_id || comment.id);
    return button;
  }

  function renderComment(comment: CommentItem): HTMLElement {
    const card = el('article', 'discussion__item');
    card.id = `comment-${comment.id}`;
    card.dataset.commentId = String(comment.id);
    card.dataset.parentId = String(comment.parent_id);
    const avatar = el('img', 'discussion__avatar');
    const member = {name:comment.author_name, avatar:comment.author_avatar, frame:comment.author_frame, badge:comment.author_badge, color:comment.author_color};
    applyMemberAvatar(avatar, member);
    const body = el('div', 'discussion__body');
    const head = el('div', 'discussion__item-head');
    head.append(createMemberName(member));
    if (!comment.is_deleted && comment.like_count >= GOD_COMMENT_LIKES) head.append(el('span', 'discussion__god', '神评'));
    head.append(el('time','',dateLabel(comment.created_at)));
    const text = el('p', comment.is_deleted ? 'discussion__deleted' : 'discussion__text', comment.is_deleted ? '评论已删除' : comment.content);
    const actions = el('div', 'discussion__actions');
    if (!comment.is_deleted) {
      const like = action('like', '', comment);
      like.innerHTML = `${iconMarkup('heart', 14)} <span>${comment.like_count}</span>`;
      like.dataset.liked = String(comment.liked);
      like.setAttribute('aria-label', comment.liked ? '取消点赞' : '点赞');
      actions.append(like, action('reply', '回复', comment));
      if (getUser()?.id === comment.user_id) actions.append(action('delete', '删除', comment));
    }
    if (comment.parent_id === 0) actions.append(action('thread', `查看回复 (${comment.reply_count})`, comment));
    body.append(head, text, actions);
    card.append(avatar, body);
    return card;
  }

  async function loadRoots(reset = false) {
    const nextPage = reset ? 1 : page + 1;
    more.disabled = true;
    try {
      const result = await listComments(targetType, targetId, nextPage, 20, 0, sort);
      if (reset) { list.replaceChildren(); loaded = 0; }
      result.data.forEach((comment) => {
        if (!list.querySelector(`[data-comment-id="${comment.id}"]`)) list.append(renderComment(comment));
      });
      page = nextPage;
      loaded += result.data.length;
      total = result.total;
      count.textContent = `(${total})`;
      if (!total) {
        const empty = el('div', 'discussion__empty');
        const image = el('img');
        image.src = '/brand/bllii-symbol.svg';
        image.alt = '';
        empty.append(image, el('h3', '', '还没有评论'), el('p', '', '成为第一个评论的人吧'));
        list.append(empty);
      }
      more.hidden = loaded >= total;
    } catch (error) {
      if (reset) list.replaceChildren(el('p', 'discussion__muted', error instanceof Error ? error.message : '评论加载失败'));
      setMessage(error instanceof Error ? error.message : '评论加载失败', true);
    } finally { more.disabled = false; }
  }

  async function loadReplies(rootId: number, holder: HTMLElement) {
    holder.replaceChildren(el('p', 'discussion__muted', '正在加载回复…'));
    let replyPage = 1;
    const replies = el('div', 'discussion__replies');
    const load = async () => {
      const result = await listComments(targetType, targetId, replyPage, 100, rootId);
      if (replyPage === 1) holder.replaceChildren(replies);
      result.data.forEach((reply) => {
        if (!holder.querySelector(`[data-comment-id="${reply.id}"]`)) replies.append(renderComment(reply));
      });
      holder.querySelector('[data-reply-more]')?.remove();
      if (!result.total) holder.append(el('p', 'discussion__muted', '暂无回复'));
      if (replyPage * 100 < result.total) {
        const button = el('button', 'discussion__more', '加载更多回复');
        button.type = 'button';
        button.dataset.replyMore = String(rootId);
        button.onclick = async () => { button.disabled = true; replyPage++; await load(); };
        holder.append(button);
      }
    };
    try { await load(); } catch (error) { holder.replaceChildren(el('p', 'discussion__muted', error instanceof Error ? error.message : '回复加载失败')); }
  }

  async function showThread(rootCard: HTMLElement, rootId: number) {
    let holder = rootCard.querySelector<HTMLElement>('.discussion__thread');
    if (holder) { holder.remove(); return; }
    holder = el('div', 'discussion__thread');
    rootCard.querySelector('.discussion__body')?.append(holder);
    await loadReplies(rootId, holder);
  }

  function showReplyForm(card: HTMLElement, parentId: number, rootId: number) {
    section.querySelector('.discussion__reply-form')?.remove();
    const form = el('div', 'discussion__reply-form');
    const textarea = el('textarea') as HTMLTextAreaElement;
    textarea.maxLength = 2000;
    textarea.rows = 2;
    textarea.placeholder = '写下回复';
    textarea.setAttribute('aria-label', '回复内容');
    const send = el('button', '', '发送回复');
    send.type = 'button';
    const cancel = el('button', 'discussion__cancel', '取消');
    cancel.type = 'button';
    cancel.onclick = () => form.remove();
    const status = el('span', 'discussion__status');
    send.onclick = async () => {
      if (!requireLogin()) return;
      const content = textarea.value.trim();
      if (!content) { status.textContent = '回复内容不能为空'; return; }
      send.disabled = true;
      try {
        const created = await createComment(targetType, targetId, content, parentId);
        form.remove();
        if(created.pending){setMessage('已提交管理员审核，通过后才会展示');return}
        announceChange(1);
        const rootCard = section.querySelector<HTMLElement>(`[data-comment-id="${rootId}"]`);
        if (rootCard) {
          let holder = rootCard.querySelector<HTMLElement>('.discussion__thread')
            || (spotlight.contains(rootCard) ? spotlight.querySelector<HTMLElement>(':scope > .discussion__thread') : null);
          if (!holder) {
            holder = el('div', 'discussion__thread');
            rootCard.querySelector('.discussion__body')?.append(holder);
          }
          await loadReplies(rootId, holder);
          let selected = holder.querySelector<HTMLElement>(`[data-comment-id="${created.id}"]`);
          if (!selected) {
            selected = renderComment(created);
            (holder.querySelector('.discussion__replies') || holder).append(selected);
          }
          section.querySelectorAll('.discussion__highlight').forEach(item => item.classList.remove('discussion__highlight'));
          selected.classList.add('discussion__highlight');
          selected.scrollIntoView({ block: 'center' });
          try {
            const root = await getComment(rootId);
            rootCard.querySelectorAll<HTMLButtonElement>('[data-action="thread"]').forEach(button => {
              button.textContent = `查看回复 (${root.reply_count})`;
            });
          } catch { /* The reply is already visible; the count can refresh later. */ }
        } else await showSpotlight(created);
      } catch (error) { status.textContent = error instanceof Error ? error.message : '回复失败'; }
      finally { send.disabled = false; }
    };
    form.append(textarea, send, cancel, status);
    card.querySelector('.discussion__body')?.append(form);
    textarea.focus();
  }

  async function showSpotlight(comment: CommentItem) {
    spotlight.hidden = true;
    spotlight.replaceChildren();
    section.querySelectorAll('.discussion__highlight').forEach(item => item.classList.remove('discussion__highlight'));
    let visible = list.querySelector<HTMLElement>(`[data-comment-id="${comment.id}"]`);
    if (!visible && comment.root_id) {
      const rootCard = list.querySelector<HTMLElement>(`[data-comment-id="${comment.root_id}"]`);
      if (rootCard) {
        let holder = rootCard.querySelector<HTMLElement>('.discussion__thread');
        if (!holder) {
          holder = el('div', 'discussion__thread');
          rootCard.querySelector('.discussion__body')?.append(holder);
        }
        await loadReplies(comment.root_id, holder);
        visible = holder.querySelector<HTMLElement>(`[data-comment-id="${comment.id}"]`);
        if (!visible) {
          visible = renderComment(comment);
          (holder.querySelector('.discussion__replies') || holder).append(visible);
        }
      }
    }
    if (visible) {
      visible.classList.add('discussion__highlight');
      visible.scrollIntoView({ block: 'center' });
      return;
    }
    spotlight.hidden = false;
    spotlight.replaceChildren(el('h3', 'discussion__spotlight-title', '当前评论'));
    if (comment.root_id) {
      try {
        const root = await getComment(comment.root_id);
        spotlight.append(renderComment(root));
        const holder = el('div', 'discussion__thread');
        spotlight.append(holder);
        await loadReplies(root.id, holder);
        const match = holder.querySelector<HTMLElement>(`[data-comment-id="${comment.id}"]`);
        if (!match) holder.prepend(renderComment(comment));
      } catch { spotlight.append(renderComment(comment)); }
    } else spotlight.append(renderComment(comment));
    const selected = spotlight.querySelector<HTMLElement>(`[data-comment-id="${comment.id}"]`);
    selected?.classList.add('discussion__highlight');
    selected?.scrollIntoView({ block: 'center' });
  }

  submit.onclick = async () => {
    if (!requireLogin()) return;
    const content = input.value.trim();
    if (!content) { setMessage('评论内容不能为空', true); return; }
    submit.disabled = true;
    setMessage('');
    try {
      const created = await createComment(targetType, targetId, content);
      input.value = '';
      if(created.pending){setMessage('已提交管理员审核，通过后才会展示');return}
      announceChange(1);
      spotlight.hidden = true;
      spotlight.replaceChildren();
      await loadRoots(true);
      let selected = list.querySelector<HTMLElement>(`[data-comment-id="${created.id}"]`);
      if (!selected) {
        list.querySelector('.discussion__empty')?.remove();
        selected = renderComment(created);
        list.prepend(selected);
      }
      selected.classList.add('discussion__highlight');
      selected.scrollIntoView({ block: 'center' });
      setMessage('评论成功');
    } catch (error) { setMessage(error instanceof Error ? error.message : '评论失败', true); }
    finally { submit.disabled = false; }
  };

  more.onclick = () => loadRoots();
  section.querySelectorAll<HTMLButtonElement>('[data-sort]').forEach((button) => button.addEventListener('click', () => {
    const next = (button.dataset.sort || 'latest') as CommentSort;
    if (next === sort) return;
    sort = next;
    section.querySelectorAll<HTMLButtonElement>('[data-sort]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.sort === sort)));
    void loadRoots(true);
  }));
  section.addEventListener('click', async (event) => {
    const button = (event.target as Element).closest<HTMLButtonElement>('[data-action]');
    if (!button || !section.contains(button)) return;
    const id = Number(button.dataset.id);
    const rootId = Number(button.dataset.root);
    const card = button.closest<HTMLElement>('[data-comment-id]');
    if (!card) return;
    if (button.dataset.action === 'thread') { await showThread(card, rootId); return; }
    if (!requireLogin()) return;
    if (button.dataset.action === 'reply') { showReplyForm(card, id, rootId); return; }
    if (button.disabled) return;
    if (button.dataset.action === 'delete') {
      button.disabled = true;
      if (!await confirmAction('删除评论', '删除后这条评论将不再展示，已有回复会保留。确认删除吗？', {acceptLabel:'删除评论',danger:true})) { button.disabled = false; return; }
    }
    button.disabled = true;
    try {
      if (button.dataset.action === 'like') {
        const result = await setCommentLike(id, button.dataset.liked !== 'true');
        section.querySelectorAll<HTMLButtonElement>(`[data-action="like"][data-id="${id}"]`).forEach(like => {
          like.dataset.liked = String(result.liked);
          like.innerHTML = `${iconMarkup('heart', 14)} <span>${result.like_count}</span>`;
          like.setAttribute('aria-label', result.liked ? '取消点赞' : '点赞');
        });
        // 最热排序下，被点赞的顶层评论即时挪到最前，保持「热」的手感
        if (sort === 'hot' && card.parentElement === list && card.dataset.parentId === '0') list.prepend(card);
      } else if (button.dataset.action === 'delete') {
        await deleteComment(id);
        announceChange(-1);
        await loadRoots(true);
        if (!spotlight.hidden) {
          const focused = spotlight.querySelector<HTMLElement>('.discussion__highlight');
          if (focused) await showSpotlight(await getComment(Number(focused.dataset.commentId)));
        }
      }
    } catch (error) { setMessage(error instanceof Error ? error.message : '操作失败', true); }
    finally { button.disabled = false; }
  });

  updateIdentity();
  window.addEventListener('auth-changed', () => { updateIdentity(); void loadRoots(true); });
  void loadRoots(true).then(async () => {
    const id = Number(new URLSearchParams(location.search).get('comment_id'));
    if (!id) return;
    try {
      const comment = await getComment(id);
      if (comment.target_type === targetType && comment.target_id === targetId) await showSpotlight(comment);
    } catch { setMessage('这条评论已不可访问', true); }
  });
}
