// Dialog shells are rendered by Astro; actions only update text and open them.
let queue: Promise<unknown> = Promise.resolve();
let lastFocus: HTMLElement | null = null;
let trackingFocus = false;

export function initDialogs() {
  if (!trackingFocus) {
    trackingFocus = true;
    document.addEventListener('focusin', event => {
      if (event.target instanceof HTMLElement && event.target.matches('button,a,input,textarea,select,[tabindex]')) lastFocus = event.target;
    });
  }
  document.querySelectorAll<HTMLDialogElement>('.brand-dialog').forEach(dialog => {
    if (dialog.dataset.initialized) return;
    dialog.dataset.initialized = 'true';
    dialog.querySelector('[data-dialog-close]')?.addEventListener('click', () => dialog.close('cancel'));
    dialog.addEventListener('click', event => {
      if (event.target !== dialog) return;
      const rect = dialog.getBoundingClientRect();
      if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close('cancel');
    });
    let previousFocus: HTMLElement | null = null;
    dialog.addEventListener('close', () => {
      document.body.classList.toggle('dialog-open', Boolean(document.querySelector('.brand-dialog[open]')));
      const restoreFocus = previousFocus;
      // Let the awaiting action restore disabled controls before returning focus.
      setTimeout(() => {
        if (!document.querySelector('.brand-dialog[open]') && restoreFocus?.isConnected) restoreFocus.focus({preventScroll:true});
      }, 0);
    });
    dialog.addEventListener('brand-dialog-open', () => {
      const active = document.activeElement;
      previousFocus = active instanceof HTMLElement && active !== document.body ? active : lastFocus;
      document.body.classList.add('dialog-open');
    });
  });
}

export function openDialog(dialog: HTMLDialogElement) {
  initDialogs();
  if (dialog.open) return;
  dialog.returnValue = '';
  dialog.dispatchEvent(new Event('brand-dialog-open'));
  dialog.showModal();
}

export function confirmAction(title: string, description: string, options: { acceptLabel?: string; cancelLabel?: string; danger?: boolean } = {}): Promise<boolean> {
  const request = queue.then(() => new Promise<boolean>(resolve => {
    const dialog = document.getElementById('site-confirm') as HTMLDialogElement | null;
    if (!dialog) { resolve(false); return; }
    const accept = dialog.querySelector<HTMLButtonElement>('[data-confirm-accept]')!;
    const cancel = dialog.querySelector<HTMLButtonElement>('[data-confirm-cancel]')!;
    dialog.querySelector('[data-dialog-title]')!.textContent = title;
    dialog.querySelector('[data-confirm-description]')!.textContent = description;
    dialog.querySelector('[data-dialog-close]')!.setAttribute('aria-label', `关闭${title}`);
    accept.textContent = options.acceptLabel || '确认';
    cancel.textContent = options.cancelLabel || '取消';
    dialog.dataset.danger = String(Boolean(options.danger));
    const yes = () => dialog.close('accept');
    const no = () => dialog.close('cancel');
    const finish = () => {
      accept.removeEventListener('click', yes);
      cancel.removeEventListener('click', no);
      resolve(dialog.returnValue === 'accept');
    };
    accept.addEventListener('click', yes);
    cancel.addEventListener('click', no);
    dialog.addEventListener('close', finish, {once:true});
    openDialog(dialog);
    cancel.focus();
  }));
  queue = request.catch(() => false);
  return request;
}
