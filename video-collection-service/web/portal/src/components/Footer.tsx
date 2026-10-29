import React, { useState, useEffect } from 'react';
import BrandIcon from './BrandIcon';

interface FriendLink {
  name: string;
  url: string;
  description?: string;
}

interface SiteConfigData {
  site_name?: string;
  site_subtitle?: string;
  site_contact_email?: string;
  site_contact_group?: string;
  site_disclaimer?: string;
  friend_links?: FriendLink[];
}

export default function Footer({ initialConfig }: { initialConfig?: SiteConfigData }) {
  const [config, setConfig] = useState<SiteConfigData>(
    initialConfig || {
      site_name: 'bllii 动漫聚合',
      site_subtitle: '追番库 • 让生活多一种可能',
      site_disclaimer:
        '本站所有视频资源均系第三方公开网络接口与网络爬虫自动检索聚合，本站服务器不存储、不制作、不上传任何视听节目及视频文件。若相关内容无意侵犯了贵司版权或合法权益，请通过上方联系方式提供权利证明与侵权链接，我们将在收到通知后24小时内断开相关播放解析并配合清理。本站提倡支持正版影视与动漫。',
      friend_links: []
    }
  );

  useEffect(() => {
    fetch('/api/site/config')
      .then((res) => res.json())
      .then((json) => {
        if (json && json.code === 1 && json.data) {
          const d = json.data;
          let fl: FriendLink[] = [];
          if (d.site_friend_links) {
            try {
              fl = JSON.parse(d.site_friend_links);
            } catch {}
          }
          setConfig((prev) => ({
            ...prev,
            site_contact_email: d.site_contact_email || prev.site_contact_email,
            site_contact_group: d.site_contact_group || prev.site_contact_group,
            site_disclaimer: d.site_disclaimer || prev.site_disclaimer,
            friend_links: fl.length ? fl : prev.friend_links
          }));
        }
      })
      .catch(() => {});
  }, []);

  const friendLinks = config.friend_links || [];

  return (
    <footer className="border-t border-slate-200/80 bg-white/95 backdrop-blur-md pt-12 pb-8 text-xs text-slate-500 mt-16 transition-colors">
      <div className="max-w-[1360px] mx-auto px-4 sm:px-6">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-12 gap-8 pb-10 border-b border-slate-100">
          <div className="lg:col-span-4 flex flex-col gap-3">
            <div className="flex items-center gap-2">
              <img src="/brand/bllii-horizontal.svg" alt="bllii" width="140" height="54" />
              <span className="sr-only">{config.site_name || 'bllii 动漫聚合'}</span>
            </div>
            <p className="text-slate-500 leading-relaxed text-xs sm:text-[13px] mt-1 pr-4">
              {config.site_subtitle || '追番库 • 让生活多一种可能'}
              。精选全网正版与优质二次元动漫、剧场版及新番流媒体资源，智能聚合秒播，致力于为动漫爱好者提供极速舒适的追番体验。
            </p>
            <div className="flex items-center gap-3 mt-2 text-slate-400">
              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-emerald-50 text-emerald-600 font-medium text-[11px]">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></span>
                More Stories, Together
              </span>
              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-primary-50 text-primary-600 font-medium text-[11px]">
                智能同系列推荐
              </span>
            </div>
          </div>

          <div className="lg:col-span-4 flex flex-col gap-3">
            <h3 className="text-sm font-bold text-slate-800 flex items-center gap-2">
              <BrandIcon name="mail" size={20} className="w-4 h-4 text-primary-600" />
              <span>联系方式</span>
            </h3>
            <ul className="space-y-2.5 text-xs text-slate-600">
              <li className="flex items-center gap-2 group">
                <span className="text-slate-400 shrink-0">联系邮箱：</span>
                <a
                  href={config.site_contact_email ? `mailto:${config.site_contact_email}` : undefined}
                  className="text-primary-600 hover:text-primary-700 font-medium hover:underline transition-colors truncate"
                >
                  {config.site_contact_email || '暂未设置'}
                </a>
              </li>
              <li className="flex items-center gap-2">
                <span className="text-slate-400 shrink-0">官方社群：</span>
                <span className="text-slate-700 font-medium truncate">
                  {config.site_contact_group || '暂未设置'}
                </span>
              </li>
              <li className="pt-1">
                <a
                  href="/community"
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-primary-50 text-primary-600 hover:bg-primary-100 font-medium text-xs transition-colors"
                >
                  <BrandIcon name="message" size={16} className="w-3.5 h-3.5" />
                  <span>前往留言求片反馈</span>
                </a>
              </li>
            </ul>
          </div>

          <div className="lg:col-span-4 flex flex-col gap-3">
            <h3 className="text-sm font-bold text-slate-800 flex items-center gap-2">
              <BrandIcon name="link" size={20} className="w-4 h-4 text-primary-600" />
              <span>友情链接</span>
            </h3>
            <div className="flex flex-wrap gap-2 pt-1">
              {friendLinks.length === 0 && <span className="text-slate-400">暂无友情链接</span>}
              {friendLinks.map((link) => (
                <a
                  key={link.url}
                  href={link.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  title={link.description || link.name}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-100 hover:bg-primary-50 text-slate-600 hover:text-primary-600 border border-transparent hover:border-primary-100 text-xs font-medium transition-all group"
                >
                  <span>{link.name}</span>
                  <BrandIcon
                    name="arrow-right"
                    size={16}
                    className="w-3 h-3 text-slate-400 group-hover:text-primary-500 opacity-60 group-hover:opacity-100 transition-opacity"
                  />
                </a>
              ))}
            </div>
          </div>
        </div>

        <div className="flex-1 space-y-1 py-4">
          <p className="text-slate-600 leading-relaxed text-xs">{config.site_disclaimer}</p>
        </div>

        <div className="brand-masthead">
          <a href="/" aria-label="bllii 首页"></a>
          <p>
            好 动 画 · 更 好 的 你<small>SAME STORIES. A BRIGHTER YOU.</small>
          </p>
        </div>

        <div className="flex flex-col sm:flex-row items-center justify-between gap-3 pt-4 text-slate-400 text-xs">
          <div className="flex items-center gap-3 flex-wrap">
            <span>© 2026 bllii • 二次元番剧聚合平台</span>
          </div>
          <div className="flex items-center gap-4 text-slate-500">
            <a href="/community" className="hover:text-primary-600 transition-colors">
              留言求片
            </a>
            <a href="#" className="hover:text-primary-600 transition-colors">
              用户协议
            </a>
            <a href="#" className="hover:text-primary-600 transition-colors">
              隐私保护
            </a>
            <a href="#" className="hover:text-primary-600 transition-colors">
              版权申明
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
