import { iconMarkup } from './brand-icons';

interface PocketStory { id: number; name: string; picture: string; }
const key = 'bllii_story_pocket';
const limit = 24;

export function initStoryPocket() {
  const dialog = document.querySelector<HTMLDialogElement>('[data-pocket-dialog]');
  if (!dialog) return;
  const list = dialog.querySelector<HTMLElement>('[data-pocket-list]')!;
  const read = (): PocketStory[] => {
    try {
      const saved: unknown = JSON.parse(localStorage.getItem(key) || '[]');
      if (!Array.isArray(saved)) return [];
      return saved.filter((item): item is PocketStory => !!item && Number.isInteger(item.id) && item.id > 0 && typeof item.name === 'string' && typeof item.picture === 'string').slice(0, limit);
    } catch { return []; }
  };
  let stories = read();
  let noticeTimer: ReturnType<typeof setTimeout>;
  const notice = (message: string) => {
    const el = document.querySelector<HTMLElement>('[data-story-notice]')!;
    el.querySelector('span')!.textContent = message; el.hidden = false;
    clearTimeout(noticeTimer); noticeTimer = setTimeout(() => el.hidden = true, 2200);
  };
  const write = () => {
    try { localStorage.setItem(key, JSON.stringify(stories)); return true; }
    catch { notice('故事口袋暂时无法保存'); return false; }
  };
  const render = () => {
    document.querySelectorAll<HTMLButtonElement>('[data-pocket-id]').forEach(button => {
      const saved = stories.some(story => story.id === Number(button.dataset.pocketId));
      button.setAttribute('aria-pressed', String(saved));
      button.title = saved ? '移出故事口袋' : '放进故事口袋';
      button.setAttribute('aria-label', button.title);
    });
    const count = document.querySelector<HTMLElement>('[data-pocket-count]')!;
    count.textContent = String(stories.length); count.hidden = !stories.length;
    dialog.querySelector('[data-pocket-total]')!.textContent = String(stories.length);
    dialog.querySelector<HTMLElement>('[data-pocket-empty]')!.hidden = !!stories.length;
    dialog.querySelector('[data-pocket-limit]')!.textContent = stories.length ? `${stories.length} / ${limit}` : '';
    list.replaceChildren();
    stories.forEach(story => {
      const row = document.createElement('article'); row.className = 'pocket-row';
      const cover = document.createElement('img'); cover.alt = ''; cover.src = story.picture || '/brand/bllii-app-light.svg';
      cover.onerror = () => { cover.onerror = null; cover.src = '/brand/bllii-app-light.svg'; };
      const title = document.createElement('a'); title.href = `/anime/${story.id}`; title.className = 'pocket-row__title'; title.textContent = story.name;
      const play = document.createElement('a'); play.href = `/play/${story.id}`; play.className = 'icon-command'; play.title = '立即观看'; play.setAttribute('aria-label', `观看 ${story.name}`); play.innerHTML = iconMarkup('play');
      const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'icon-command'; remove.title = '移出故事口袋'; remove.setAttribute('aria-label', `移出 ${story.name}`); remove.innerHTML = iconMarkup('close', 16);
      remove.onclick = () => {
        const previous = stories;
        stories = stories.filter(item => item.id !== story.id);
        if (!write()) stories = previous;
        render();
        dialog.querySelector<HTMLButtonElement>('.pocket-row button')?.focus();
      };
      row.append(cover, title, play, remove); list.append(row);
    });
  };
  document.addEventListener('click', event => {
    const button = (event.target as Element).closest<HTMLButtonElement>('[data-pocket-id]');
    if (!button) return;
    const id = Number(button.dataset.pocketId);
    if (!Number.isInteger(id) || id <= 0) return;
    const exists = stories.some(story => story.id === id);
    if (!exists && stories.length >= limit) { notice('故事口袋已满'); return; }
    const previous = stories;
    stories = exists ? stories.filter(story => story.id !== id) : [{ id, name: button.dataset.pocketName || '', picture: button.dataset.pocketPicture || '' }, ...stories];
    if (!write()) { stories = previous; return; }
    render(); notice(exists ? '已移出故事口袋' : '已放进故事口袋');
    if (!matchMedia('(prefers-reduced-motion: reduce)').matches && !exists) {
      button.animate([{ boxShadow: '0 0 0 0 #ff89c780' }, { boxShadow: '0 0 0 10px #ff89c700' }], { duration: 480, easing: 'ease-out' });
      button.querySelector('svg')?.animate([{ clipPath: 'inset(100% 0 0)' }, { clipPath: 'inset(0)' }], { duration: 320, easing: 'ease-out' });
    }
  });
  document.querySelector('[data-open-pocket]')?.addEventListener('click', () => { render(); dialog.showModal(); });
  dialog.querySelector('[data-pocket-close]')?.addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
  window.addEventListener('storage', event => { if (event.key === key) { stories = read(); render(); } });
  render();

  if (!matchMedia('(prefers-reduced-motion: reduce)').matches) document.querySelectorAll<HTMLImageElement>('.video-card__cover img').forEach(image => {
    if (image.complete) return;
    image.addEventListener('load', () => image.animate([{ opacity: .2 }, { opacity: 1 }], { duration: 250, easing: 'ease-out' }), { once: true });
  });

  const progress = document.querySelector<HTMLElement>('[data-reading-progress]')!;
  const backTop = document.querySelector<HTMLButtonElement>('[data-back-top]')!;
  let scheduled = false;
  const updateProgress = () => {
    scheduled = false;
    const height = document.documentElement.scrollHeight - innerHeight;
    progress.style.transform = `scaleX(${height > 0 ? Math.min(1, scrollY / height) : 0})`;
    backTop.hidden = scrollY < 600;
  };
  const schedule = () => { if (!scheduled) { scheduled = true; requestAnimationFrame(updateProgress); } };
  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule);
  backTop.onclick = () => window.scrollTo({ top: 0, behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
  updateProgress();
}
