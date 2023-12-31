import { growthRequest as api } from './growth';
import { checkMe, getToken, type User } from './auth';
import { iconMarkup } from './brand-icons';
import { confirmAction } from './dialogs';

interface Level { level: number; name: string; threshold: number }
interface Mission { key: string; name: string; description: string; kind: string; period: string; target: number; progress: number; reward: number; claimed: boolean; href: string }
interface Journey { experience: number; level: Level; next_level: Level | null; levels: Level[]; missions: Mission[] }
interface Cosmetic { id: number; name: string; kind: string; value: string; price: number; owned: boolean; equipped: boolean }
interface Wish { id: number; user_id: number; username: string; title: string; details: string; reply: string; status: string; cost: number; shared: boolean; support_count: number; supported: boolean; created_at: string }
interface Rules { active: number; checkin: number; streak_step: number; streak_cap: number; request_cost: number }
interface Wallet { balance: number; checked_in: boolean; streak: number; day: string; rules: Rules; ledger: { reason: string; amount: number; balance: number; created_at: string }[] }

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const station = document.querySelector<HTMLElement>('.growth-station')!;
const kinds: Record<string,string> = { avatar:'头像', animated_avatar:'动态头像', frame:'头像框', badge:'铭牌', nickname_color:'彩色昵称' };
const missionIcons: Record<string,string> = { history:'play', favorite:'bookmark', comment:'message', checkin:'calendar', support:'heart' };
const states: Record<string,string> = { pending:'待处理', processing:'寻找中', fulfilled:'故事已找到', rejected:'未采纳 · 已退款' };
let wallet: Wallet | null = null, journey: Journey | null = null, user: User | null = null;
let catalog: Cosmetic[] = [], wishes: Wish[] = [], requests: Wish[] = [];
let filter = '', wallPage = 1, wallTotal = 0, requestPage = 1, requestTotal = 0, busy = false, trial: Cosmetic | null = null;

function node<K extends keyof HTMLElementTagNameMap>(tag: K, text = '', cls = ''): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag); el.textContent = text; if (cls) el.className = cls; return el;
}
function icon(name: string, cls = 'g-icon-tile') {
  const el = node('span', '', cls);
  // Only fixed, local icon names use SVG markup. All API content uses textContent.
  el.innerHTML = iconMarkup(name, 19); return el;
}
function empty(title: string, description: string) {
  const el = node('div', '', 'g-empty'), img = node('img');
  img.src = '/brand/bllii-symbol.svg'; img.alt = '';
  el.append(img, node('strong', title), node('p', description)); return el;
}
function safeColor(value: string) { return /^#[0-9a-f]{6}$/i.test(value) ? value : ''; }
function date(value: string) { return new Date(value).toLocaleString('zh-CN', { timeZone:'Asia/Shanghai', month:'numeric', day:'numeric', hour:'2-digit', minute:'2-digit' }); }
function status(text: string, error = false) {
  $('growth-status').hidden = !text; $('growth-status').textContent = text; $('growth-status').dataset.error = String(error);
}
function canPublishWish() { return !!getToken() && !!user && !['observer','operator'].includes(user.role); }
function mutationButton(text: string, work: () => Promise<void>, cls = 'brand-button') {
  const el = node('button', text, cls); el.type = 'button'; el.dataset.mutate = '';
  el.disabled = busy || !getToken(); el.addEventListener('click', () => void action(work)); return el;
}
async function action(work: () => Promise<void>) {
  if (busy) return;
  busy = true; station.setAttribute('aria-busy','true');
  station.querySelectorAll<HTMLButtonElement>('[data-mutate]').forEach(b => b.disabled = true);
  try { await work(); } catch (e) { status((e as Error).message, true); }
  finally {
    busy = false; station.setAttribute('aria-busy','false'); render();
  }
}
function selectTab(key: string, focus = false) {
  if (!['daily','wardrobe','wishes','ledger'].includes(key)) key = 'daily';
  station.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach(tab => {
    const selected = tab.dataset.tab === key; tab.setAttribute('aria-selected',String(selected)); tab.tabIndex = selected ? 0 : -1;
    $('panel-'+tab.dataset.tab).hidden = !selected; if (selected && focus) tab.focus();
  });
  const url = new URL(location.href); url.searchParams.set('tab',key); history.replaceState(null,'',url);
}
function renderMember() {
  const decorations = { ...(user?.decorations || {}) };
  let avatar = user?.avatar || '/brand/bllii-symbol.svg';
  if (trial) {
    if (trial.kind === 'avatar' || trial.kind === 'animated_avatar') avatar = trial.value;
    if (trial.kind === 'frame') decorations.frame = trial.value;
    if (trial.kind === 'badge') decorations.badge = trial.value;
    if (trial.kind === 'nickname_color') decorations.nickname_color = trial.value;
  }
  const img = $<HTMLImageElement>('member-avatar'); img.src = avatar;
  img.style.borderColor = safeColor(decorations.frame || '') || 'white';
  $('member-name').textContent = user?.nickname || user?.username || '故事里的新朋友';
  $('member-name').style.color = safeColor(decorations.nickname_color || '');
  $('member-badge').textContent = decorations.badge || ''; $('member-badge').hidden = !decorations.badge;
  $('tryon-note').hidden = !trial;
}
function renderOverview() {
  $('guest-hint').hidden = !!getToken(); renderMember();
  $<HTMLButtonElement>('submit-request').disabled = busy || !wallet || !canPublishWish();
  $<HTMLButtonElement>('checkin').disabled = busy || !wallet || wallet.checked_in || !getToken();
  $('balance').textContent = wallet ? String(wallet.balance) : '—';
  if (journey) {
    const { level, next_level: next, experience, levels } = journey;
    $('member-level').textContent = `Lv.${level.level} · ${level.name}`;
    $('experience').textContent = next ? `${experience} / ${next.threshold} 成长值` : `${experience} 成长值`;
    $('level-note').textContent = next ? `再积累 ${next.threshold-experience} 成长值，成为「${next.name}」` : '陪伴已经成为星光，继续收藏你的故事吧。';
    $<HTMLProgressElement>('level-progress').value = next ? Math.min(100,(experience-level.threshold)/(next.threshold-level.threshold)*100) : 100;
    $('level-stops').replaceChildren(...levels.map(l => { const el = node('span',l.name); el.dataset.reached = String(experience >= l.threshold); return el; }));
  }
  const route = $('checkin-route'); route.replaceChildren();
  const streak = wallet?.streak || 0, checked = wallet?.checked_in || false;
  const start = Math.floor(Math.max(0,streak-(checked ? 1 : 0))/7)*7;
  for (let i = 1; i <= 7; i++) {
    const day = start+i, tile = node('div','','g-day');
    tile.dataset.done = String(day <= streak); tile.dataset.next = String(!checked && day === streak+1);
    tile.append(node('small',`第${day}天`), icon(day <= streak ? 'heart' : 'star',''));
    const r = wallet?.rules;
    tile.append(node('strong',r ? `+${Math.min(r.streak_cap,r.checkin+(day-1)*r.streak_step)}` : '—'));
    route.append(tile);
  }
  if (wallet) {
    const r = wallet.rules;
    $('streak').textContent = `连续相伴 ${streak} 天`;
    $('checkin').textContent = checked ? '今天已相见' : '签到领积分';
    $('checkin-note').textContent = checked ? '今天的星光已收好，明天再相见。' : `今天签到可收下 ${Math.min(r.streak_cap,r.checkin+streak*r.streak_step)} 积分。`;
    $('rules').textContent = `每日活跃 +${r.active}；签到基础 ${r.checkin}，连续签到每天增加 ${r.streak_step}，单日上限 ${r.streak_cap}。按北京时间重置，断签后从第一天开始。`;
    $('request-rule').textContent = `每次心愿 ${r.request_cost} 积分，未采纳全额退还。最多同时提交5个未完成心愿。`;
  }
}
function renderMissions() {
  const list = $('missions'); list.replaceChildren();
  if (!journey) { list.append(empty(getToken() ? '成长进度尚未加载' : '旅程，从第一份喜欢开始',getToken() ? '点击刷新进度重新获取。' : '登录后可以领取日常与成就奖励。')); return; }
  if (!journey.missions.length) { list.append(empty('暂时没有成长任务','先去发现一部喜欢的作品吧。')); return; }
  for (const m of journey.missions) {
    const card = node('article','','g-mission'), top = node('div','','g-mission-top'), footer = node('div','','g-mission-footer');
    top.append(icon(missionIcons[m.kind] || 'star'),node('span',`+${m.reward} 积分`,'g-reward'));
    footer.append(node('small',`${m.period === 'day' ? '每日' : '成就'} · ${m.progress}/${m.target}`));
    if (m.claimed || m.progress >= m.target) {
      const button = mutationButton(m.claimed ? '已收下' : '领取星光',async () => { const r = await api('/api/user/missions/claim',{key:m.key}); status(r.data.earned ? `收下 ${r.data.earned} 积分，热爱又多了一点。` : '这份奖励已经领取过了。'); await loadMember(); });
      button.disabled ||= m.claimed; footer.append(button);
    } else {
      const link = node('a',m.kind === 'checkin' ? '去签到' : m.kind === 'support' ? '去亮灯' : '去完成','brand-outline'); link.href = m.href;
      if (m.kind === 'support' || m.kind === 'checkin') link.addEventListener('click',e => { e.preventDefault(); if (m.kind === 'support') selectTab('wishes'); else { $('checkin').focus(); $('checkin').scrollIntoView({block:'center',behavior:'smooth'}); } });
      footer.append(link);
    }
    card.append(top,node('h3',m.name),node('p',m.description),footer); list.append(card);
  }
}
function renderShop() {
  const list = $('shop'); list.replaceChildren();
  $('owned-count').textContent = `已珍藏 ${catalog.filter(c => c.owned).length} 件装扮`;
  const items = catalog.filter(c => !filter || (filter === 'owned' ? c.owned : c.kind === filter));
  if (!items.length) { list.append(empty('衣橱里还有新的可能',getToken() ? '这个分区暂时没有装扮，看看其他分区吧。' : '登录后开启装扮衣橱。')); return; }
  for (const c of items) {
    const card = node('article','','g-shop-item'), preview = node('div','','g-shop-preview'), visual = node('div','','g-cosmetic'); visual.dataset.kind = c.kind;
    if (c.kind === 'avatar' || c.kind === 'animated_avatar') { const img = node('img'); img.src = c.value; img.alt = c.name; img.loading = 'lazy'; visual.append(img); }
    else if (c.kind === 'frame') { visual.style.borderColor = safeColor(c.value); visual.append(icon('user','')); }
    else { visual.textContent = c.kind === 'badge' ? c.value : (user?.nickname || '你的名字'); if (c.kind === 'nickname_color') visual.style.color = safeColor(c.value); }
    preview.append(visual);
    const details = node('div','','g-shop-details'); details.append(node('h3',c.name),node('small',kinds[c.kind]));
    const actions = node('div','','g-shop-actions'), tryon = node('button','试戴','brand-outline'); tryon.type = 'button';
    tryon.addEventListener('click',() => { trial = c; renderMember(); $('member-avatar').scrollIntoView({block:'center',behavior:'smooth'}); });
    const button = mutationButton(c.equipped ? '卸下' : c.owned ? '佩戴' : '兑换',async () => {
      if (!c.owned) {
        if (!await confirmAction('把这份喜欢收入衣橱',`兑换「${c.name}」需要 ${c.price} 积分。兑换后永久拥有，随时更换，成长等级不会降低。`)) return;
        await api('/api/user/shop/redeem',{id:c.id}); status('已收入衣橱，点击佩戴就能展示你的新装扮。');
      } else { await api('/api/user/shop/equip',{id:c.equipped ? 0 : c.id,slot:c.kind === 'animated_avatar' ? 'avatar' : c.kind}); status(c.equipped ? '装扮已卸下。' : '装扮已佩戴，名片也一起更新了。'); }
      trial = null; await loadMember();
    });
    if (!c.owned && wallet && wallet.balance < c.price) { button.textContent = '积分不足'; button.disabled = true; }
    actions.append(tryon,button); card.append(preview,details,node('p',c.equipped ? '正在佩戴' : c.owned ? '已收入衣橱' : `${c.price} 积分`,'g-shop-state'),actions); list.append(card);
  }
}
function renderWall() {
  const list = $('wish-wall'); list.replaceChildren();
  if (!wishes.length) list.append(empty('还没有公开的心愿','把你的期待写下来，或等候下一位同好点亮这里。'));
  for (const wish of wishes) {
    const card = node('article','','g-wish'), head = node('div','','g-wish-head'), info = node('div'), footer = node('div','','g-wish-footer');
    info.append(node('h3',wish.title),node('small',`${wish.username} · ${states[wish.status]}`)); head.append(icon('library'),info);
    footer.append(node('small',`${wish.support_count} 位同好也在期待`));
    const button = mutationButton(wish.supported ? '已亮灯' : user?.id === wish.user_id ? '我的心愿' : getToken() ? '我也想看' : '登录后亮灯',async () => { await api('/api/user/movie-requests/support',{id:wish.id}); status('为这份期待亮了一盏灯。'); await Promise.all([loadWall(),loadMember()]); },'brand-outline');
    button.disabled ||= wish.supported || user?.id === wish.user_id || !canPublishWish(); footer.append(button);
    card.append(head,node('p',wish.details || '同好的小小期待，等待一个好消息。'),footer); list.append(card);
  }
  $('wall-page').textContent = `第 ${wallPage} 页 · ${wallTotal} 份期待`;
  $<HTMLButtonElement>('wall-prev').disabled = busy || wallPage <= 1;
  $<HTMLButtonElement>('wall-next').disabled = busy || wallPage*6 >= wallTotal;
}
function renderRequests() {
  const list = $('requests'); list.replaceChildren();
  if (!requests.length) list.append(empty('你的下一份期待，会是什么？','心愿提交后，进度与回复会收在这里。'));
  for (const wish of requests) {
    const card = node('article','','g-wish'), head = node('div','','g-wish-head'), info = node('div'), footer = node('div','','g-wish-footer');
    info.append(node('h3',wish.title),node('small',`${states[wish.status]} · ${date(wish.created_at)}`)); head.append(icon('heart'),info);
    footer.append(node('small',`${wish.cost} 积分 · ${wish.shared ? `${wish.support_count} 人助力` : '仅自己与管理员可见'}`));
    if (wish.shared || ['pending','processing'].includes(wish.status)) {
      const button = mutationButton(wish.shared ? '收回公开' : '邀请同好助力',async () => {
        if (!wish.shared && !await confirmAction('让同好一起期待',`公开后，昵称、作品名与线索会展示给所有访客。不会展示你的积分与账号名。你可以随时收回公开，已收到的助力会保留。`)) return;
        await api('/api/user/movie-requests/share',{id:wish.id,shared:!wish.shared}); status(wish.shared ? '这份心愿已恢复私密。' : '心愿已公开，等候同好的灯光。'); await Promise.all([loadRequests(),loadWall()]);
      },'brand-outline'); button.disabled ||= !canPublishWish(); footer.append(button);
    }
    card.append(head,node('p',wish.reply || '管理员正在等待处理这份心愿。'),footer); list.append(card);
  }
  $('requests-more').hidden = requests.length >= requestTotal;
  $<HTMLButtonElement>('requests-more').disabled = busy;
}
function renderLedger() {
  const list = $('ledger'); list.replaceChildren();
  if (!wallet?.ledger.length) { list.append(empty('星光的足迹，还在等待第一笔','签到、完成任务或收下一件装扮，都会留下记录。')); return; }
  for (const entry of wallet.ledger) {
    const row = node('div','','g-ledger-row'), copy = node('div'), amount = node('div','','g-ledger-amount');
    copy.append(node('strong',entry.reason),node('small',date(entry.created_at)));
    amount.dataset.income = String(entry.amount >= 0); amount.append(node('b',`${entry.amount >= 0 ? '+' : ''}${entry.amount}`),node('small',`余额 ${entry.balance}`));
    row.append(icon(entry.amount >= 0 ? 'star' : 'bookmark'),copy,amount); list.append(row);
  }
}
function render() { renderOverview(); renderMissions(); renderShop(); renderWall(); renderRequests(); renderLedger(); }
async function loadMember() {
  const [p,s,j,u] = await Promise.all([api('/api/user/points'),api('/api/user/shop'),api('/api/user/journey'),checkMe()]);
  if (!u) throw new Error('登录已过期，请重新登录。');
  wallet = p.data; catalog = s.data; journey = j.data; user = u; window.dispatchEvent(new Event('auth-changed'));
}
async function loadWall(page = wallPage) {
  const token = getToken(); const r = await fetch(`/api/movie-request-wall?page=${page}&page_size=6`,{ headers: token ? {Authorization:`Bearer ${token}`} : {} });
  const result = await r.json(); if (!r.ok || result.code !== 1) throw new Error(result.error || '心愿榜暂时不可用');
  wallPage = page; wishes = result.data; wallTotal = result.total;
}
async function loadRequests(page = 1) {
  const r = await api(`/api/user/movie-requests?page=${page}&page_size=6`);
  requestPage = page; requests = page === 1 ? r.data : [...requests,...r.data]; requestTotal = r.total;
}

station.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((tab,i,tabs) => {
  tab.addEventListener('click',() => selectTab(tab.dataset.tab!));
  tab.addEventListener('keydown',e => {
    const indices: Record<string,number> = { ArrowRight:(i+1)%tabs.length, ArrowLeft:(i+tabs.length-1)%tabs.length, Home:0, End:tabs.length-1 };
    if (e.key in indices) { e.preventDefault(); selectTab(tabs[indices[e.key]].dataset.tab!,true); }
  });
});
station.querySelectorAll<HTMLButtonElement>('[data-filter]').forEach(button => button.addEventListener('click',() => {
  filter = button.dataset.filter!; station.querySelectorAll('[data-filter]').forEach(b => b.setAttribute('aria-pressed',String((b as HTMLElement).dataset.filter === filter))); renderShop();
}));
$('reset-tryon').addEventListener('click',() => { trial = null; renderMember(); });
$('checkin').addEventListener('click',() => void action(async () => { const r = await api('/api/user/points/checkin',{}); status(r.data.earned ? `今天的星光已收下：+${r.data.earned} 积分。` : '今天已经签到，明天再相见。'); await loadMember(); }));
$('refresh-growth').addEventListener('click',() => void action(async () => { if (!getToken()) { status('登录后开启成长旅程。'); return; } await loadMember(); status('成长进度已更新。'); }));
$('refresh-wall').addEventListener('click',() => void action(async () => { await loadWall(1); }));
$('wall-prev').addEventListener('click',() => void action(async () => { await loadWall(wallPage-1); }));
$('wall-next').addEventListener('click',() => void action(async () => { await loadWall(wallPage+1); }));
$('requests-more').addEventListener('click',() => void action(async () => { await loadRequests(requestPage+1); }));
$('movie-request').addEventListener('submit',e => {
  e.preventDefault(); void action(async () => {
    if (!wallet || !canPublishWish()) throw new Error('当前账号无法提交心愿。');
    const title = $<HTMLInputElement>('request-title').value.trim(); if (!title) throw new Error('请写下想看的作品名。');
    if (!await confirmAction('收好这份观影期待',`提交「${title}」将使用 ${wallet.rules.request_cost} 积分。未采纳会全额退还，心愿默认保持私密。`)) return;
    await api('/api/user/movie-requests',{title,details:$<HTMLTextAreaElement>('request-details').value});
    $<HTMLFormElement>('movie-request').reset(); status('心愿已收好，处理进度会通过站内消息告诉你。'); await Promise.all([loadMember(),loadRequests()]);
  });
});
selectTab(new URLSearchParams(location.search).get('tab') || 'daily');
renderOverview();
void action(async () => {
  const results = await Promise.allSettled([loadWall(),...(getToken() ? [loadMember(),loadRequests()] : [])]);
  const failed = results.find(r => r.status === 'rejected'); if (failed?.status === 'rejected') throw failed.reason;
});
