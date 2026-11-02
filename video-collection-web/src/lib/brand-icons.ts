export function iconMarkup(name: string, size = 20): string {
  return `<svg class="brand-icon" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><use href="/brand/bllii-ui.svg#bllii-${name}" /></svg>`;
}

export function setIcon(element: Element | null, name: string) {
  element?.querySelector('use')?.setAttribute('href', `/brand/bllii-ui.svg#bllii-${name}`);
}
