export interface MemberAppearance { name?: string; avatar?: string; frame?: string; badge?: string; color?: string; }
export function memberColor(value?: string) { return /^#[0-9a-f]{6}$/i.test(value || '') ? value! : ''; }
export function memberAvatar(value?: string) {
  if (value && (/^https?:\/\//i.test(value) || (value.startsWith('/') && !value.startsWith('//')))) return value;
  return '/brand/bllii-symbol.svg';
}
export function applyMemberAvatar(image: HTMLImageElement, member: MemberAppearance) {
  image.classList.add('member-avatar');
  image.src = memberAvatar(member.avatar);
  image.alt = `${member.name || '同好'}的头像`;
  image.style.setProperty('--member-frame', memberColor(member.frame) || '#f0eafa');
  image.onerror = () => { image.onerror = null; image.src = '/brand/bllii-symbol.svg'; };
}
export function createMemberName(member: MemberAppearance) {
  const name = document.createElement('span'); name.className = 'member-name';
  const label = document.createElement('strong'); label.textContent = member.name || '匿名用户';
  label.style.color = memberColor(member.color);
  name.append(label);
  if (member.badge) {
    const badge = document.createElement('span'); badge.className = 'member-badge';
    badge.textContent = member.badge; badge.setAttribute('aria-label',`铭牌：${member.badge}`);
    name.append(badge);
  }
  return name;
}
