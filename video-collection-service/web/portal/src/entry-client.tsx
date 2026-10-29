import React from 'react';
import { hydrateRoot, createRoot } from 'react-dom/client';
import App from './App';
import './styles/bundle.css';

const el = document.getElementById('__WF_DATA__');
const props = el && el.textContent ? JSON.parse(el.textContent) : {};
const rootEl = document.getElementById('root');

if (rootEl) {
  const currentUrl = window.location.pathname + window.location.search;
  if (rootEl.hasChildNodes()) {
    hydrateRoot(rootEl, <App url={currentUrl} {...props} />);
  } else {
    createRoot(rootEl).render(<App url={currentUrl} {...props} />);
  }
}
