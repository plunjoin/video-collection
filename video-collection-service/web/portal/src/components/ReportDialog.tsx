import React, { useState } from 'react';

export interface ReportTarget {
  targetType: 'video' | 'news' | 'post' | 'wiki_subject';
  targetId: number;
  label: string; // 展示用上下文，如「词条：星穹使魔物语」
}

// 纠错弹层：提交到通用反馈接口（type=report，携带纠错对象上下文），
// 管理员在后台「用户反馈」中看到对象与说明后处理。
export default function ReportDialog({ target, onClose }: { target: ReportTarget; onClose: () => void }) {
  const [content, setContent] = useState('');
  const [contact, setContact] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState('');

  const submit = async () => {
    const text = content.trim();
    if (!text || submitting) return;
    setSubmitting(true);
    setError('');
    try {
      const res = await fetch('/api/feedback', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          type: 'report',
          title: `【纠错】${target.label}`,
          content: text,
          contact: contact.trim(),
          target_type: target.targetType,
          target_id: target.targetId,
        }),
      });
      const json = await res.json();
      if (json && json.code === 1) {
        setDone(true);
      } else {
        setError(json?.error || json?.msg || '提交失败，请稍后再试');
      }
    } catch {
      setError('网络错误，请稍后再试');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-[80] flex items-center justify-center bg-slate-900/50 p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-2xl bg-white p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {done ? (
          <div className="text-center py-4">
            <div className="text-3xl mb-2">🙏</div>
            <h3 className="text-base font-bold text-slate-800 mb-1">纠错已提交</h3>
            <p className="text-xs text-slate-400 mb-4">感谢你的贡献，管理员会尽快核实处理。</p>
            <button
              onClick={onClose}
              className="px-5 py-2 rounded-xl bg-[#597bea] text-white text-sm font-semibold"
            >
              知道了
            </button>
          </div>
        ) : (
          <>
            <h3 className="text-base font-bold text-slate-800">纠错反馈</h3>
            <p className="text-xs text-slate-400 mt-1 mb-3">对象：{target.label}</p>
            <textarea
              value={content}
              onChange={(e) => setContent(e.target.value)}
              rows={4}
              maxLength={500}
              placeholder="请描述哪里有误，例如：演员名写错 / 剧情简介过期 / 关系缺失…"
              className="w-full rounded-xl border border-slate-200 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300 resize-none"
            />
            <input
              value={contact}
              onChange={(e) => setContact(e.target.value)}
              maxLength={100}
              placeholder="联系方式（选填，方便回访）"
              className="w-full mt-2 rounded-xl border border-slate-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
            />
            {error && <p className="text-xs text-rose-500 mt-2">{error}</p>}
            <div className="mt-4 flex justify-end gap-2">
              <button
                onClick={onClose}
                className="px-4 py-2 rounded-xl bg-slate-50 border border-slate-200 text-slate-600 text-sm font-semibold"
              >
                取消
              </button>
              <button
                onClick={submit}
                disabled={submitting || !content.trim()}
                className="px-5 py-2 rounded-xl bg-[#597bea] hover:bg-[#4b6fd6] disabled:opacity-50 text-white text-sm font-semibold"
              >
                {submitting ? '提交中...' : '提交纠错'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
