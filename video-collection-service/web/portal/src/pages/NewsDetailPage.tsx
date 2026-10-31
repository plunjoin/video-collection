import React, { useEffect, useState } from 'react';
import Layout from '../layouts/Layout';
import MemberIdentity from '../components/MemberIdentity';
import Comments from '../components/Comments';
import BrandIcon from '../components/BrandIcon';
import ReportDialog, { type ReportTarget } from '../components/ReportDialog';
import { getNewsDetail, getWikiSubject, type ContentItem, type WikiSubjectBrief, type WikiSubjectInfo } from '../lib/api';

function fmtDate(d?: string): string {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return d;
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')} ${String(dt.getHours()).padStart(2, '0')}:${String(dt.getMinutes()).padStart(2, '0')}`;
}

// 关联词条卡片：资讯归属的作品/人物，可跳转词条档案
function SubjectCard({ subject }: { subject: WikiSubjectInfo }) {
  const linkedVideo = subject.linked_videos && subject.linked_videos.length > 0 ? subject.linked_videos[0] : null;
  return (
    <a href={`/wiki/${subject.id}`} className="block bg-gradient-to-r from-purple-50 to-blue-50 border border-purple-100 rounded-2xl p-4 my-6 hover:shadow-md transition-shadow">
      <div className="flex items-center gap-3">
        {subject.cover_image ? (
          <img src={subject.cover_image} alt={subject.name} className="w-12 h-16 rounded-lg object-cover shrink-0" />
        ) : (
          <span className="w-12 h-16 rounded-lg bg-purple-100 text-purple-500 flex items-center justify-center text-xs font-bold shrink-0">Wiki</span>
        )}
        <div className="min-w-0 flex-1">
          <div className="text-[11px] font-semibold text-purple-500 mb-0.5">关联词条 · {subject.sub_type || subject.type}</div>
          <div className="text-sm font-bold text-slate-800 truncate">{subject.name}</div>
          {subject.summary && <div className="text-xs text-slate-500 truncate mt-0.5">{subject.summary}</div>}
        </div>
        {linkedVideo ? (
          <span className="px-3 py-1.5 rounded-full bg-[#597bea] text-white text-xs font-semibold shrink-0">去观看</span>
        ) : (
          <span className="text-purple-400 text-sm shrink-0">›</span>
        )}
      </div>
    </a>
  );
}

export default function NewsDetailPage({ id }: { id: number }) {
  const [item, setItem] = useState<ContentItem | null>(null);
  const [subject, setSubject] = useState<WikiSubjectInfo | null>(null);
  const [authorSubject, setAuthorSubject] = useState<WikiSubjectBrief | null>(null);
  const [reportOpen, setReportOpen] = useState(false);
  const [missing, setMissing] = useState(false);

  useEffect(() => {
    let alive = true;
    getNewsDetail(id).then((result) => {
      if (!alive) return;
      if (!result) {
        setMissing(true);
        return;
      }
      setItem(result.item);
      setAuthorSubject(result.authorSubject);
      if (result.item.subject_id) {
        getWikiSubject(result.item.subject_id).then((sub) => {
          if (alive && sub) setSubject(sub);
        });
      }
    });
    return () => { alive = false; };
  }, [id]);

  useEffect(() => {
    if (missing) window.location.replace('/news');
  }, [missing]);

  if (!item) {
    return (
      <Layout title="资讯 — bllii" activeNav="资讯">
        <div className="page-content" style={{ minHeight: 220 }}></div>
      </Layout>
    );
  }

  return (
    <Layout title={`${item.title} — bllii`} activeNav="资讯">
      <div className="page-content">
        <a href="/news" className="news-back">‹ 返回资讯列表</a>

        <article className="news-article">
          {item.category ? <span className="editorial-label">{item.category}</span> : null}
          <h1>{item.title}</h1>
          <div className="news-meta">
            {item.author_name ? (
              authorSubject ? (
                <a
                  href={`/wiki/${authorSubject.id}`}
                  className="inline-flex items-center gap-1 hover:opacity-80"
                  title={`查看 ${authorSubject.name} 的词条档案（作品、关系网络）`}
                >
                  <MemberIdentity
                    name={item.author_name}
                    avatar={item.author_avatar}
                    frame={item.author_frame}
                    badge={item.author_badge}
                    color={item.author_color}
                  />
                  <span className="text-[11px] font-semibold text-purple-500 bg-purple-50 border border-purple-100 rounded-full px-2 py-0.5">词条 ›</span>
                </a>
              ) : (
                <MemberIdentity
                  name={item.author_name}
                  avatar={item.author_avatar}
                  frame={item.author_frame}
                  badge={item.author_badge}
                  color={item.author_color}
                />
              )
            ) : null}
            <time>{fmtDate(item.published_at || item.created_at)}</time>
            {item.like_count > 0 ? <span><BrandIcon name="heart" size={14} /> {item.like_count}</span> : null}
            <button
              type="button"
              onClick={() => setReportOpen(true)}
              className="ml-auto text-[11px] text-slate-400 hover:text-blue-500 underline underline-offset-2"
            >
              纠错
            </button>
          </div>

          {item.cover ? (
            <img
              src={item.cover}
              alt={item.title}
              className="news-cover"
              onError={(event) => { const img = event.currentTarget; img.onerror = null; img.style.display = 'none'; }}
            />
          ) : null}

          {subject ? <SubjectCard subject={subject} /> : null}

          {item.summary ? <p className="news-summary">{item.summary}</p> : null}

          <div className="news-body" style={{ whiteSpace: 'pre-wrap' }}>{item.content}</div>
        </article>
        <Comments targetType="news" targetId={item.id} />
      </div>
      {reportOpen && (
        <ReportDialog
          target={{ targetType: 'news', targetId: item.id, label: `资讯：${item.title}` } as ReportTarget}
          onClose={() => setReportOpen(false)}
        />
      )}
    </Layout>
  );
}
