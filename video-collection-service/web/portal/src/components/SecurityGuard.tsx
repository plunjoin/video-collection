import React, { useEffect } from 'react';

export default function SecurityGuard() {
  useEffect(() => {
    // 仅在生产环境启用基础保护（若有需要）
    if (process.env.NODE_ENV !== 'production') return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'F12' || e.keyCode === 123) {
        e.preventDefault();
        return false;
      }
      const isCtrlOrMeta = e.ctrlKey || e.metaKey;
      if (isCtrlOrMeta && e.shiftKey) {
        const key = (e.key || '').toUpperCase();
        if (key === 'I' || key === 'J' || key === 'C') {
          e.preventDefault();
          return false;
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown, true);
    return () => {
      window.removeEventListener('keydown', handleKeyDown, true);
    };
  }, []);

  return null;
}
