import React, { useEffect } from 'react';
import BrandIcon from './BrandIcon';
import BrandDialog from './BrandDialog';
import { initStoryPocket } from '../lib/story-pocket';

export default function StoryPocket() {
  useEffect(() => {
    initStoryPocket();
  }, []);

  return (
    <>
      <div className="page-reading-line" aria-hidden="true">
        <span data-reading-progress></span>
      </div>
      <aside className="story-tools" aria-label="故事工具">
        <button className="story-tool" data-open-pocket aria-label="故事口袋" title="故事口袋">
          <BrandIcon name="library" />
          <span data-pocket-count hidden>0</span>
        </button>
        <button className="story-tool" data-back-top aria-label="回到顶部" title="回到顶部" hidden>
          <BrandIcon name="arrow-up" />
        </button>
      </aside>
      <BrandDialog
        id="story-pocket"
        title="故事口袋"
        titleExtra={<small data-pocket-total>0</small>}
        footer={
          <>
            <span>留一点期待，给下一次相遇。</span>
            <span data-pocket-limit></span>
          </>
        }
      >
        <div className="pocket-list" data-pocket-list></div>
        <div className="pocket-empty" data-pocket-empty>
          <img src="/brand/bllii-symbol.svg" alt="" />
          <h3>下一份喜欢，还在路上</h3>
          <a href="/category">
            发现番剧 <BrandIcon name="arrow-right" size={16} />
          </a>
        </div>
      </BrandDialog>
      <div className="story-notice" data-story-notice role="status" aria-live="polite" hidden>
        <BrandIcon name="bookmark" size={18} />
        <span></span>
      </div>
    </>
  );
}
