import React from 'react';
import BrandIcon from './BrandIcon';

const items = [
  {
    name: '新番时间表',
    href: '/latest',
    icon: 'calendar'
  },
  {
    name: '排行榜',
    href: '/rank',
    icon: 'rank'
  },
  {
    name: '资讯',
    href: '/news',
    icon: 'library'
  },
  {
    name: '专属合集',
    href: '/category',
    icon: 'compass'
  },
  {
    name: '追番列表',
    href: '/follow',
    icon: 'bookmark'
  }
];

export default function QuickNav() {
  return (
    <section className="brand-section quick-nav">
      <div className="py-2">
        <div className="grid grid-cols-5 gap-2 sm:gap-6">
          {items.map((item) => (
            <a
              key={item.href}
              href={item.href}
              className="flex flex-col items-center justify-center gap-2 group p-1 sm:p-2 rounded-xl transition-colors"
            >
              <div className="w-11 h-11 sm:w-14 sm:h-14 rounded-2xl flex items-center justify-center bg-slate-100 text-slate-500 group-hover:bg-primary-50 group-hover:text-primary-600 transition-colors">
                <BrandIcon name={item.icon} size={28} />
              </div>
              <span className="text-xs sm:text-sm font-medium text-slate-700 group-hover:text-[#3f6fd8] transition-colors text-center">
                {item.name}
              </span>
            </a>
          ))}
        </div>
      </div>
    </section>
  );
}
