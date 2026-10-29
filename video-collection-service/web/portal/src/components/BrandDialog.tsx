import React from 'react';
import BrandIcon from './BrandIcon';

interface Props {
  id: string;
  title: string;
  descriptionId?: string;
  className?: string;
  titleExtra?: React.ReactNode;
  children?: React.ReactNode;
  footer?: React.ReactNode;
}

export default function BrandDialog({
  id,
  title,
  descriptionId,
  className = '',
  titleExtra,
  children,
  footer
}: Props) {
  return (
    <dialog
      id={id}
      className={`brand-dialog ${className}`.trim()}
      aria-labelledby={`${id}-title`}
      aria-describedby={descriptionId}
    >
      <header className="brand-dialog__header">
        <img src="/brand/bllii-symbol.svg" width="38" height="38" alt="" />
        <h2 id={`${id}-title`} data-dialog-title>
          {title}
          {titleExtra}
        </h2>
        <button
          type="button"
          className="brand-dialog__close"
          data-dialog-close
          aria-label={`关闭${title}`}
        >
          <BrandIcon name="close" size={18} />
        </button>
      </header>
      <div className="brand-dialog__body">{children}</div>
      <footer className="brand-dialog__footer">{footer}</footer>
    </dialog>
  );
}
