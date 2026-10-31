import React, { useEffect, useState } from 'react';
import Layout from '../layouts/Layout';
import ReportDialog, { type ReportTarget } from '../components/ReportDialog';
import { getWikiSubject, getNewsList, type WikiSubjectInfo, type ContentItem } from '../lib/api';

// Wiki 词条档案页：属性卡、摘要、演职员关系、关联视频与相关资讯
export default function WikiSubjectPage({ id }: { id: number }) {
  const [subject, setSubject] = useState<WikiSubjectInfo | null>(null);
  const [news, setNews] = useState<ContentItem[]>([]);
  const [missing, setMissing] = useState(false);
  const [reportOpen, setReportOpen] = useState(false);

  useEffect(() => {
    let alive = true;
    getWikiSubject(id).then((result) => {
      if (!alive) return;
      if (!result) setMissing(true);
      else setSubject(result);
    });
    getNewsList({ pageSize: 10 }).then((list) => {
      if (alive) setNews((list.data || []).filter((n) => n.subject_id === id));
    });
    return () => { alive = false; };
  }, [id]);

  if (missing) {
    return (
      <Layout title="词条不存在 — bllii" activeNav="">
        <div className="py-24 text-center text-slate-400">
          <p>词条不存在或已被删除。</p>
          <a href="/" className="mt-4 inline-block text-blue-500 font-medium">返回首页 →</a>
        </div>
      </Layout>
    );
  }

  if (!subject) {
    return (
      <Layout title="正在载入词条..." activeNav="">
        <div className="py-24 text-center text-slate-400 text-sm">正在加载词条档案...</div>
      </Layout>
    );
  }

  const relations = [...(subject.forward_relations || []), ...(subject.reverse_relations || [])];
  const infoboxEntries = Object.entries(subject.infobox || {}).filter(([, v]) => v !== null && v !== undefined && String(v).trim() !== '');

  return (
    <Layout title={`${subject.name} - bllii 知识库`} activeNav="" description={`${subject.name} 的 Wiki 词条档案`}>
      <div className="max-w-[1360px] mx-auto px-4 sm:px-6 pt-6 pb-16">
        <a href="/" className="text-xs text-slate-400 hover:text-blue-500">‹ 返回首页</a>

        <div className="bg-white rounded-3xl p-6 sm:p-8 shadow-sm border border-slate-100 flex flex-col md:flex-row gap-8 mt-3 mb-8">
          <div className="w-40 sm:w-48 shrink-0 aspect-[3/4] rounded-2xl overflow-hidden shadow-md bg-purple-50">
            {subject.cover_image ? (
              <img src={subject.cover_image} alt={subject.name} className="w-full h-full object-cover" />
            ) : (
              <div className="w-full h-full flex items-center justify-center text-purple-300 text-4xl font-black">wiki</div>
            )}
          </div>
          <div className="flex-1">
            <div className="flex items-center gap-2 mb-2 flex-wrap">
              <span className="px-2.5 py-0.5 rounded-full text-xs font-semibold bg-purple-50 text-purple-600">
                {subject.sub_type || subject.type}
              </span>
              {subject.aliases && subject.aliases.length > 0 && (
                <span className="text-xs text-slate-400">别名：{subject.aliases.join('、')}</span>
              )}
            </div>
            <h1 className="text-2xl sm:text-3xl font-bold text-slate-800 mb-1">{subject.name}</h1>
            {subject.original_name && subject.original_name !== subject.name && (
              <div className="text-sm text-slate-400 mb-3">{subject.original_name}</div>
            )}
            <div className="text-sm text-slate-600 leading-relaxed whitespace-pre-wrap">
              {subject.summary || '暂无词条简介。'}
            </div>

            {infoboxEntries.length > 0 && (
              <dl className="mt-5 grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-2 text-xs">
                {infoboxEntries.map(([k, v]) => (
                  <div key={k} className="flex gap-2 min-w-0">
                    <dt className="text-slate-400 shrink-0">{k}</dt>
                    <dd className="text-slate-700 truncate" title={String(v)}>{String(v)}</dd>
                  </div>
                ))}
              </dl>
            )}
            <div className="mt-4">
              <button
                type="button"
                onClick={() => setReportOpen(true)}
                className="text-xs text-slate-400 hover:text-blue-500 underline underline-offset-2"
              >
                词条信息有误？提交纠错
              </button>
            </div>
          </div>
        </div>

        {relations.length > 0 && (
          <div className="bg-white rounded-3xl p-6 shadow-sm border border-slate-100 mb-8">
            <h2 className="text-base font-bold text-slate-800 mb-4">关系网络</h2>
            <div className="flex flex-wrap gap-2">
              {relations.map((rel) => {
                const peer = rel.target_subject || rel.source_subject;
                if (!peer) return null;
                const isWork = peer.type === 'work';
                return (
                  <a
                    key={rel.id}
                    href={isWork && subject.linked_videos && subject.linked_videos.length > 0
                      ? `/wiki/${peer.id}`
                      : `/wiki/${peer.id}`}
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-slate-50 hover:bg-purple-50 border border-slate-100 text-xs text-slate-700"
                    title={`${rel.relation_type}${rel.role_description ? '：' + rel.role_description : ''}`}
                  >
                    <span className={`w-2 h-2 rounded-full ${peer.type === 'person' ? 'bg-purple-400' : peer.type === 'work' ? 'bg-blue-400' : 'bg-emerald-400'}`}></span>
                    <span className="font-medium">{peer.name}</span>
                    {rel.role_description && <span className="text-slate-400">· {rel.role_description}</span>}
                  </a>
                );
              })}
            </div>
          </div>
        )}

        {subject.linked_videos && subject.linked_videos.length > 0 && (
          <div className="bg-white rounded-3xl p-6 shadow-sm border border-slate-100 mb-8">
            <h2 className="text-base font-bold text-slate-800 mb-4">可观看的正片</h2>
            <div className="space-y-3">
              {subject.linked_videos.map((v) => (
                <a key={v.id} href={`/anime/${v.id}`} className="flex items-center gap-3 group">
                  <img src={v.picture || '/brand/bllii-app-blue.svg'} alt={v.name} className="w-14 h-20 rounded-lg object-cover shrink-0" />
                  <div className="min-w-0">
                    <div className="text-sm font-semibold text-slate-700 group-hover:text-blue-600">{v.name}</div>
                    <div className="text-xs text-slate-400 mt-0.5">{[v.type_name, v.year, v.remarks].filter(Boolean).join(' · ')}</div>
                  </div>
                </a>
              ))}
            </div>
          </div>
        )}

        {news.length > 0 && (
          <div className="bg-white rounded-3xl p-6 shadow-sm border border-slate-100">
            <h2 className="text-base font-bold text-slate-800 mb-4">相关资讯</h2>
            <div className="space-y-3">
              {news.map((item) => (
                <a key={item.id} href={`/news/${item.id}`} className="block group">
                  <div className="text-sm font-semibold text-slate-700 group-hover:text-blue-600">{item.title}</div>
                  {item.summary && <div className="text-xs text-slate-400 truncate mt-0.5">{item.summary}</div>}
                </a>
              ))}
            </div>
          </div>
        )}
      </div>
      {reportOpen && subject && (
        <ReportDialog
          target={{ targetType: 'wiki_subject', targetId: subject.id, label: `词条：${subject.name}` } as ReportTarget}
          onClose={() => setReportOpen(false)}
        />
      )}
    </Layout>
  );
}
