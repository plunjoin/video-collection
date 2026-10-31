import React, { useState, useEffect } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';
import VideoCard from '../components/VideoCard';
import ReportDialog, { type ReportTarget } from '../components/ReportDialog';
import { getVideoDetail, ragAsk, type VideoRecord, type PlayGroup, type WikiSubjectInfo, type RagAskResult, type ContentItem } from '../lib/api';

interface Props {
  id?: string;
  detail?: { video: VideoRecord; related: VideoRecord[]; wiki?: WikiSubjectInfo | null; relatedNews?: ContentItem[]; related_news?: ContentItem[] };
}

const RELATION_LABELS: Record<string, string> = {
  actor: '声优 / 演员',
  cv: '配音',
  suit_actor: '皮套演员',
  martial_arts: '动作指导',
  director: '导演',
  character_play: '饰演角色',
  belongs_to_era: '所属纪元',
  sequel: '系列续作',
};

function relationLabel(type: string): string {
  return RELATION_LABELS[type] || type;
}

// 词条详情页的演职员区块：按关系类型分组展示人物与角色，人名可进入词条档案
function WikiCastSection({ wiki }: { wiki: WikiSubjectInfo }) {
  const relations = [...(wiki.forward_relations || []), ...(wiki.reverse_relations || [])];
  if (relations.length === 0) return null;

  const groups = new Map<string, { label: string; people: { id: number; name: string; role: string; subType: string }[] }>();
  for (const rel of relations) {
    const peer = rel.target_subject || rel.source_subject;
    if (!peer || peer.type !== 'person') continue;
    const label = relationLabel(rel.relation_type);
    if (!groups.has(rel.relation_type)) {
      groups.set(rel.relation_type, { label, people: [] });
    }
    groups.get(rel.relation_type)!.people.push({
      id: peer.id,
      name: peer.name,
      role: rel.role_description || '',
      subType: peer.sub_type || '',
    });
  }
  if (groups.size === 0) return null;

  return (
    <div className="bg-white rounded-3xl p-6 shadow-sm border border-slate-100 mb-8">
      <h2 className="text-base font-bold text-slate-800 mb-4">演职员档案 <span className="text-xs font-normal text-slate-400">点击人名查看词条档案与作品</span></h2>
      <div className="space-y-4">
        {[...groups.entries()].map(([type, group]) => (
          <div key={type}>
            <div className="text-xs font-semibold text-slate-400 mb-2">{group.label}</div>
            <div className="flex flex-wrap gap-2">
              {group.people.map((p, idx) => {
                const inner = (
                  <>
                    <span
                      className="flex items-center justify-center font-bold shrink-0 rounded-full text-white"
                      style={{ width: 20, height: 20, fontSize: 10, background: 'linear-gradient(135deg,#4b9fff,#9a83ff)' }}
                    >
                      {p.name.slice(0, 1)}
                    </span>
                    <span className="font-medium">{p.name}</span>
                    {p.role && <span className="text-slate-400">· {p.role}</span>}
                  </>
                );
                const cls = "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-slate-50 border border-slate-100 text-xs text-slate-700 hover:bg-purple-50 hover:border-purple-100 transition-colors";
                return p.id > 0 ? (
                  <a
                    key={`${p.id}-${idx}`}
                    href={`/wiki/${p.id}`}
                    className={cls}
                    title={`查看 ${p.name} 的词条档案（参演作品、关系网络）`}
                  >
                    {inner}
                  </a>
                ) : (
                  <span key={`${p.id}-${idx}`} className={cls}>{inner}</span>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// 关联资讯区块
function RelatedNewsSection({ news }: { news: ContentItem[] }) {
  if (!news || news.length === 0) return null;
  return (
    <div className="bg-white rounded-3xl p-6 shadow-sm border border-slate-100 mb-8">
      <h2 className="text-base font-bold text-slate-800 mb-4">相关资讯 <span className="text-xs font-normal text-slate-400">围绕本作品与演职人员</span></h2>
      <div className="space-y-3">
        {news.map((item) => (
          <a key={item.id} href={`/news/${item.id}`} className="flex items-start gap-3 group">
            {item.cover && (
              <img src={item.cover} alt={item.title} className="w-16 h-12 rounded-lg object-cover shrink-0" />
            )}
            <div className="min-w-0">
              <div className="text-sm font-semibold text-slate-700 group-hover:text-blue-600 truncate">{item.title}</div>
              {item.summary && <div className="text-xs text-slate-400 truncate mt-0.5">{item.summary}</div>}
            </div>
          </a>
        ))}
      </div>
    </div>
  );
}

// AI 知识库问答区块（RAG，带知识库引用）
function AiAskSection({ seed }: { seed: string }) {
  const [question, setQuestion] = useState('');
  const [result, setResult] = useState<RagAskResult | null>(null);
  const [busy, setBusy] = useState(false);

  const ask = async (q: string) => {
    const text = q.trim();
    if (!text || busy) return;
    setBusy(true);
    setResult(null);
    const res = await ragAsk(text);
    setResult(res);
    setBusy(false);
  };

  return (
    <div className="bg-gradient-to-br from-blue-50 via-white to-purple-50 rounded-3xl p-6 shadow-sm border border-slate-100 mb-8">
      <h2 className="text-base font-bold text-slate-800 mb-1">问问 AI 使魔 <span className="text-xs font-normal text-slate-400">基于站内 Wiki 与资讯知识库回答</span></h2>
      <form
        className="mt-3 flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          ask(question);
        }}
      >
        <input
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder={`例如：${seed}的导演是谁？`}
          className="flex-1 px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300 bg-white"
        />
        <button
          type="submit"
          disabled={busy || !question.trim()}
          className="px-5 py-2.5 rounded-xl bg-[#597bea] hover:bg-[#4b6fd6] disabled:opacity-50 text-white font-semibold text-sm shadow-sm transition-all"
        >
          {busy ? '思考中...' : '提问'}
        </button>
      </form>

      {result && (
        <div className="mt-4 rounded-2xl bg-white/80 border border-slate-100 p-4">
          {result.mode === 'retrieval' && (
            <div className="text-xs text-amber-600 bg-amber-50 rounded-lg px-3 py-2 mb-3">{result.note}</div>
          )}
          {result.answer && (
            <div className="text-sm text-slate-700 whitespace-pre-wrap leading-relaxed">{result.answer}</div>
          )}
          {result.citations?.length > 0 && (
            <div className="mt-3 pt-3 border-t border-slate-100">
              <div className="text-xs font-semibold text-slate-400 mb-2">知识库引用</div>
              <div className="flex flex-wrap gap-1.5">
                {result.citations.slice(0, 6).map((c, idx) => {
                  const title = c.metadata?.subject_name || c.metadata?.title || c.text.slice(0, 24);
                  const ref = result.refs?.[idx];
                  const inner = (
                    <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-slate-50 border border-slate-100 text-xs text-slate-600 max-w-[280px]">
                      <span className="text-blue-500 font-bold">[{idx + 1}]</span>
                      <span className="truncate">{title}</span>
                    </span>
                  );
                  return ref?.url ? (
                    <a key={c.id} href={ref.url} className="hover:opacity-80">{inner}</a>
                  ) : (
                    <span key={c.id}>{inner}</span>
                  );
                })}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default function AnimeDetailPage({ id = '317', detail: initialDetail }: Props) {
  const [detail, setDetail] = useState<Props['detail']>(initialDetail || null);
  const [loading, setLoading] = useState(!initialDetail);
  const [reportOpen, setReportOpen] = useState(false);

  useEffect(() => {
    if (!initialDetail || (detail?.video && String(detail.video.id) !== String(id))) {
      setLoading(true);
      getVideoDetail(id)
        .then((res) => {
          if (res && res.video) setDetail(res);
        })
        .catch(() => {})
        .finally(() => setLoading(false));
    }
  }, [id]);

  if (loading) {
    return (
      <Layout title="正在载入番剧详情..." activeNav="番剧">
        <div className="py-24 text-center text-slate-400 text-sm">正在加载番剧档案...</div>
      </Layout>
    );
  }

  if (!detail || !detail.video) {
    return (
      <Layout title="未找到番剧" activeNav="番剧">
        <div className="py-24 text-center text-slate-400">
          <p>抱歉，未找到该番剧信息。</p>
          <a href="/category" className="mt-4 inline-block text-blue-500 font-medium">返回番剧库 →</a>
        </div>
      </Layout>
    );
  }

  // SSR 注水（Go 侧）用 snake_case，客户端 getVideoDetail 用 camelCase，两者都兼容
  const { video, related = [], wiki, relatedNews, related_news } = detail;
  const subjectNews = relatedNews || related_news || [];
  const playGroups: PlayGroup[] = video.play_groups || [];
  const episodes = playGroups[0]?.episodes || [];

  return (
    <Layout
      title={`${video.name} - bllii 番剧详情`}
      activeNav="番剧"
      description={`${video.name} 在线观看`}
      image={video.picture}
    >
      <div className="max-w-[1360px] mx-auto px-4 sm:px-6 pt-6 pb-16">
        {/* 顶部头部档案 */}
        <div className="bg-white rounded-3xl p-6 sm:p-8 shadow-sm border border-slate-100 flex flex-col md:flex-row gap-8 mb-8">
          <div className="w-48 sm:w-56 shrink-0 aspect-[3/4] rounded-2xl overflow-hidden shadow-md">
            <img
              src={video.picture || '/brand/bllii-app-blue.svg'}
              alt={video.name}
              className="w-full h-full object-cover"
              onError={(e) => {
                const target = e.currentTarget;
                target.onerror = null;
                target.src = '/brand/bllii-app-blue.svg';
              }}
            />
          </div>

          <div className="flex-1 flex flex-col justify-between">
            <div>
              <div className="flex items-center gap-3 mb-2">
                <span className="px-2.5 py-0.5 rounded-full text-xs font-semibold bg-blue-50 text-blue-600">
                  {video.type_name || '番剧'}
                </span>
                {wiki && (
                  <a
                    href={`/wiki-subject/${wiki.id}`}
                    className="px-2.5 py-0.5 rounded-full text-xs font-semibold bg-purple-50 text-purple-600 hover:bg-purple-100"
                    title="查看 Wiki 知识库词条"
                  >
                    Wiki 词条 #{wiki.id}
                  </a>
                )}
                {video.remarks && (
                  <span className="text-xs text-slate-500 font-medium">{video.remarks}</span>
                )}
              </div>
              <h1 className="text-2xl sm:text-3xl font-bold text-slate-800 mb-3">{video.name}</h1>
              <p className="text-xs text-slate-500 mb-4 flex flex-wrap gap-x-4 gap-y-1">
                <span>地区：{video.area || '未知'}</span>
                <span>年份：{video.year || '未知'}</span>
                <span>语言：{video.language || '未知'}</span>
                {!wiki && video.actor && <span>声优/演员：{video.actor}</span>}
                {!wiki && video.director && <span>导演：{video.director}</span>}
              </p>

              <div className="text-xs text-slate-600 leading-relaxed max-w-3xl line-clamp-4">
                {wiki?.summary || (video.content ? video.content.replace(/<[^>]+>/g, '') : '暂无详细剧情简介。')}
              </div>
            </div>

            <div className="pt-6 flex items-center gap-4">
              <a
                href={`/play/${video.id}`}
                className="px-6 py-3 rounded-2xl bg-[#597bea] hover:bg-[#4b6fd6] text-white font-semibold text-sm shadow-md transition-all flex items-center gap-2"
              >
                <BrandIcon name="play" size={18} />
                <span>立即播放</span>
              </a>
              <button
                type="button"
                className="px-5 py-3 rounded-2xl bg-slate-50 hover:bg-slate-100 text-slate-700 font-semibold text-sm border border-slate-200 transition-all flex items-center gap-2"
              >
                <BrandIcon name="heart" size={18} />
                <span>追番收藏</span>
              </button>
              <button
                type="button"
                onClick={() => setReportOpen(true)}
                className="px-4 py-3 rounded-2xl text-slate-400 hover:text-blue-500 text-xs font-semibold transition-all"
                title="发现信息有误？提交纠错给管理员"
              >
                纠错
              </button>
            </div>
          </div>
        </div>

        {/* Wiki 知识库档案：演职员关系 */}
        {wiki && <WikiCastSection wiki={wiki} />}

        {/* AI 知识库问答 */}
        <AiAskSection seed={video.name} />

        {/* 选集 */}
        {episodes.length > 0 && (
          <div className="bg-white rounded-3xl p-6 shadow-sm border border-slate-100 mb-8">
            <h2 className="text-base font-bold text-slate-800 mb-4">剧集列表 ({episodes.length}话)</h2>
            <div className="grid grid-cols-3 sm:grid-cols-6 md:grid-cols-8 gap-2.5">
              {episodes.map((ep, idx) => (
                <a
                  key={idx}
                  href={`/play/${video.id}?ep=${idx}`}
                  className="py-2.5 px-2 rounded-xl text-xs font-semibold bg-slate-50 hover:bg-blue-50 hover:text-blue-600 text-slate-700 text-center transition-all truncate border border-slate-100/80"
                  title={ep.name}
                >
                  {ep.name}
                </a>
              ))}
            </div>
          </div>
        )}

        {/* 相关资讯 */}
        <RelatedNewsSection news={subjectNews} />

        {/* 相关推荐 */}
        {related.length > 0 && (
          <div className="mb-8">
            <div className="section-heading mb-4">
              <h2>同好推荐 <span>›</span></h2>
            </div>
            <div className="video-grid">
              {related.slice(0, 6).map((item) => (
                <VideoCard key={item.id} video={item} />
              ))}
            </div>
          </div>
        )}
      </div>
      {reportOpen && (
        <ReportDialog
          target={{ targetType: 'video', targetId: video.id, label: `作品：${video.name}` } as ReportTarget}
          onClose={() => setReportOpen(false)}
        />
      )}
    </Layout>
  );
}
