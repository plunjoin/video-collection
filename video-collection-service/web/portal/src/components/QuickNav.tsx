import React from 'react';
import BrandIcon from './BrandIcon';

const items = [
  {
    name: '新番时间表',
    iconBg: 'bg-blue-100 text-blue-600',
    href: '/latest',
    icon: 'calendar'
  },
  {
    name: '排行榜',
    iconBg: 'bg-pink-100 text-pink-600',
    href: '/rank',
    icon: 'rank'
  },
  {
    name: '资讯',
    iconBg: 'bg-violet-50 text-violet-600',
    href: '/news',
    icon: 'library'
  },
  {
    name: '专属合集',
    iconBg: 'bg-emerald-50 text-emerald-600',
    href: '/category',
    icon: 'compass'
  },
  {
    name: '追番列表',
    iconBg: 'bg-blue-100 text-blue-500',
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
              className="flex flex-col items-center justify-center gap-2 group p-1 sm:p-2 rounded-xl transition-all"
            >
              <div className={`w-11 h-11 sm:w-14 sm:h-14 rounded-2xl flex items-center justify-center ${item.iconBg} shadow-sm group-hover:scale-110 group-hover:shadow-md transition-all duration-300`}>
                <BrandIcon name={item.icon} size={28} />
              </div>
              <span className="text-xs sm:text-sm font-medium text-slate-700 group-hover:text-primary-600 transition-colors tracking-tight text-center">
                {item.name}
              </span>
            </a>
          ))}
        </div>
      </div>
    </section>
  );
}
