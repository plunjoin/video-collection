import React, { useEffect } from 'react';
import type { CommentTarget } from '../lib/comments';

interface Props { targetType: CommentTarget; targetId: number; }

// 评论控件骨架：DOM 由 lib/comments-widget 接管（挂载后动态 import，幂等）。
// memo 防止父级状态变化重渲染重置 data-* 属性，避免与控件内部状态脱节。
const Comments = React.memo(function Comments({ targetType, targetId }: Props) {
  useEffect(() => { void import('../lib/comments-widget'); }, []);
  return (
    <section className="discussion" data-comment-target={targetType} data-target-id={targetId} id="comments" aria-label="评论">
      <div className="discussion__heading">
        <h2>评论 <span data-count></span></h2>
        <div className="discussion__sorts" role="group" aria-label="评论排序">
          <button type="button" data-sort="latest" aria-pressed="true">最新</button>
          <button type="button" data-sort="hot" aria-pressed="false">最热</button>
        </div>
      </div>
      <div className="discussion__compose">
        <div className="discussion__identity">
          <img data-avatar src="/brand/bllii-symbol.svg" alt="" />
          <span data-identity-name>登录后即可评论</span>
          <a data-login href="#">去登录</a>
        </div>
        <div data-compose-fields hidden>
          <textarea data-content maxLength={2000} rows={3} placeholder="写下你的评论" aria-label="评论内容"></textarea>
          <div className="discussion__compose-actions">
            <span data-message role="status"></span>
            <button type="button" data-submit>发表评论</button>
          </div>
        </div>
      </div>
      <p data-external-message className="discussion__feedback" role="status" hidden></p>
      <div data-spotlight hidden></div>
      <div data-list aria-live="polite"><p className="discussion__muted">正在加载评论…</p></div>
      <button className="discussion__more" type="button" data-more hidden>加载更多评论</button>
    </section>
  );
});

export default Comments;
