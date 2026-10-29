import React from 'react';

interface Props {
  title: string;
  description: string;
  eyebrow: string;
}

export default function PageIntro({ title, description, eyebrow }: Props) {
  return (
    <section className="page-intro">
      <div>
        <p className="page-intro__eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p className="page-intro__description">{description}</p>
      </div>
      <div className="page-intro__art" aria-hidden="true">
        <span></span>
        <img src="/brand/bllii-symbol.svg" alt="" />
      </div>
    </section>
  );
}
