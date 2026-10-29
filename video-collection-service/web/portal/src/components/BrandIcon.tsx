import React from 'react';

interface Props {
  name: string;
  size?: number;
  className?: string;
  id?: string;
}

export default function BrandIcon({ name, size = 20, className = '', id }: Props) {
  return (
    <svg
      id={id}
      className={`brand-icon ${className}`}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <use href={`/brand/bllii-ui.svg#bllii-${name}`} />
    </svg>
  );
}
