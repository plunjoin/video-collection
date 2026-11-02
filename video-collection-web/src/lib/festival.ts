// 节日皮肤：按日期识别节日，切换 CSS 变量与页面文案，制造仪式感。
// 新增节日：在下面加一条节日配置（含日期窗口与文案映射），
// 并在 styles/festival.css 里补一条 [data-festival="key"] 变量覆盖即可。

export interface Festival {
  /** 与 CSS [data-festival="key"] 对应 */
  key: string;
  /** 节日名，用于状态提示 */
  name: string;
  /** 顶部彩带文案 */
  ribbon: string;
  /** 动态文案：签到页连续天数前缀 */
  streakPrefix: string;
  /** 动态文案：未签到时节的提示 */
  checkinNote: string;
  /** 静态文案覆盖：key 对应页面里的 [data-festival-copy="key"] */
  copy: Record<string, string>;
}

/** 春节起始日（除夕），除夕起 7 天内生效。 */
const SPRING_EVES = ['2025-01-28', '2026-02-16', '2027-02-05', '2028-01-25', '2029-02-12'];
/** 周年庆：纪念项目初始化（2021-01-08），每年 1 月 5 日 - 1 月 11 日生效。
 *  month 为 0 起的 JS 月份，0 即 1 月。 */
const ANNIVERSARY = { month: 0, day: 8, span: 3 };

function inWindow(now: Date, start: Date, days: number): boolean {
  const t = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const from = new Date(start.getFullYear(), start.getMonth(), start.getDate()).getTime();
  return t >= from && t < from + days * 86400000;
}

function anniversaryYears(now: Date): number {
  return now.getFullYear() - 2021;
}

export function activeFestival(now: Date = new Date()): Festival | null {
  for (const eve of SPRING_EVES) {
    const start = new Date(`${eve}T00:00:00`);
    if (start.getFullYear() === now.getFullYear() && inWindow(now, start, 7)) return springFestival();
  }
  const an = new Date(now.getFullYear(), ANNIVERSARY.month, ANNIVERSARY.day - ANNIVERSARY.span);
  if (inWindow(now, an, ANNIVERSARY.span * 2 + 1)) return anniversaryFestival(now);
  return null;
}

function springFestival(): Festival {
  return {
    key: 'spring-festival',
    name: '春节',
    ribbon: '新春快乐 · bllii 陪你过年，好看的故事一部接一部',
    streakPrefix: '新春相伴',
    checkinNote: '新春签到，收下新年的第一份星光，年年都有好故事。',
    copy: {
      'hero-eyebrow': 'bllii / 新春放映',
      'latest-label': '新春上新',
      'checkin-title': '新春七天乐',
      'wishes-title': '新春一起追',
    },
  };
}

function anniversaryFestival(now: Date): Festival {
  const years = Math.max(1, anniversaryYears(now));
  return {
    key: 'anniversary',
    name: '周年庆',
    ribbon: `bllii ${years} 周年庆 · 谢谢每一位同好，故事因你更好看`,
    streakPrefix: '周年相伴',
    checkinNote: '周年这天的星光格外亮，签到收下这份纪念。',
    copy: {
      'hero-eyebrow': `bllii / ${years} 周年放映`,
      'latest-label': '周年上新',
      'checkin-title': '周年七天乐',
      'wishes-title': '周年一起追',
    },
  };
}

/** 入口：按当前日期在 <html> 上打 data-festival（驱动 CSS 变量），
 *  替换 [data-festival-copy] 静态文案，并填充节日彩带。传 null 可强制关闭。 */
export function applyFestival(root: ParentNode = document, festival: Festival | null = activeFestival()): Festival | null {
  const html = root.querySelector('html') || (root as Document).documentElement;
  if (!festival) {
    if (html instanceof HTMLElement) html.removeAttribute('data-festival');
    root.querySelectorAll('[data-festival-copy]').forEach((el) => el.removeAttribute('data-festival-active'));
    root.querySelectorAll('[data-festival-ribbon]').forEach((el) => ((el as HTMLElement).hidden = true));
    return null;
  }
  if (html instanceof HTMLElement) html.dataset.festival = festival.key;
  root.querySelectorAll<HTMLElement>('[data-festival-copy]').forEach((el) => {
    const replacement = festival.copy[el.dataset.festivalCopy || ''];
    if (!replacement) return;
    if (!el.dataset.festivalDefault) el.dataset.festivalDefault = el.textContent || '';
    el.textContent = replacement;
    el.dataset.festivalActive = 'true';
  });
  root.querySelectorAll<HTMLElement>('[data-festival-ribbon]').forEach((el) => {
    if (el.dataset.festivalRibbonReady === 'true') return;
    el.dataset.festivalRibbonReady = 'true';
    el.innerHTML = `<span class="festival-ribbon__spark" aria-hidden="true"></span><span class="festival-ribbon__text"></span>`;
    el.querySelector<HTMLElement>('.festival-ribbon__text')!.textContent = festival.ribbon;
    el.hidden = false;
  });
  return festival;
}
