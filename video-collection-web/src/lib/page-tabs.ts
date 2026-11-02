document.querySelectorAll<HTMLElement>('[data-page-switcher]').forEach(root => {
  const tabs = [...root.querySelectorAll<HTMLButtonElement>('[data-page-tab]')];
  const panels = [...root.querySelectorAll<HTMLElement>('[data-page-panel]')];
  const activate = (index: number, focus = false) => {
    tabs.forEach((tab, i) => {
      tab.setAttribute('aria-selected', String(i === index));
      tab.tabIndex = i === index ? 0 : -1;
    });
    panels.forEach((panel, i) => panel.hidden = i !== index);
    if (focus) tabs[index]?.focus();
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => activate(index));
    tab.addEventListener('keydown', event => {
      let next = index;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      else if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      else return;
      event.preventDefault(); activate(next, true);
    });
  });
  activate(0);
});
