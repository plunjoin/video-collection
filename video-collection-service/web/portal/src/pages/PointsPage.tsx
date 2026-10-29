import React, { useEffect } from 'react';
import Layout from '../layouts/Layout';
import BrandIcon from '../components/BrandIcon';

// 同好成长站：骨架与旧 points.astro 完全一致（lib/growth-station 按这些 id 接管 DOM），
// 挂载后动态 import 驱动脚本；脚本为模块级单例，路由内多次进入不会重复初始化。
const wardrobeFilters: Array<[string, string]> = [
  ['', '全部装扮'],
  ['owned', '我的衣橱'],
  ['avatar', '头像'],
  ['animated_avatar', '动态头像'],
  ['frame', '头像框'],
  ['badge', '铭牌'],
  ['nickname_color', '彩色昵称'],
];

export default function PointsPage() {
  useEffect(() => { void import('../lib/growth-station'); }, []);

  return (
    <Layout title="同好成长站 — bllii" activeNav="追番">
      <div className="page-content growth-station" aria-busy="false">
        <div id="growth-status" role="status" aria-live="polite" hidden></div>
        <div id="guest-hint" className="g-guest" hidden><BrandIcon name="star" /><p>每一份喜欢，都值得被珍藏。登录后开启你的成长旅程。</p><a className="brand-button" href="/login?redirect=/points">开启旅程 <BrandIcon name="arrow-right" size={16} /></a></div>
        <div className="g-overview">
          <section className="g-pass" aria-labelledby="pass-title">
            <div className="g-heading"><h2 id="pass-title"><BrandIcon name="user" size={18} />我的同好通行证</h2><a href="/notifications" aria-label="查看我的消息"><BrandIcon name="bell" size={18} />消息</a></div>
            <div className="g-member"><img id="member-avatar" src="/brand/bllii-symbol.svg" alt="我的头像" width={64} height={64} /><div><strong id="member-name">故事里的新朋友</strong><div className="g-member-labels"><span id="member-level" className="g-label">成长旅程待开启</span><span id="member-badge" className="g-nameplate" hidden></span></div></div><div className="g-balance"><span>可用积分</span><strong id="balance">—</strong></div></div>
            <div className="g-level-copy"><span id="level-note">成长值随热爱累积，兑换装扮不会降低等级。</span><span id="experience">—</span></div>
            <progress id="level-progress" max={100} value={0} aria-label="成长等级进度"></progress>
            <div id="level-stops" className="g-level-stops" aria-label="成长等级路线"></div>
            <p id="tryon-note" className="g-tryon-note" hidden>正在试戴，尚未修改你的装扮。<button id="reset-tryon" type="button">恢复当前装扮</button></p>
          </section>
          <section className="g-checkin" aria-labelledby="checkin-title">
            <div className="g-heading"><h2 id="checkin-title"><BrandIcon name="calendar" size={18} /><span data-festival-copy="checkin-title">七日相伴</span></h2><span id="streak" className="g-muted">每天一点新的期待</span></div>
            <div id="checkin-route" className="g-checkin-route" aria-label="七日签到路线"></div>
            <div className="g-checkin-bottom"><p id="checkin-note">回来看看喜欢的故事，顺手收下一点星光。</p><button id="checkin" className="brand-button" data-mutate type="button" disabled>签到领积分</button></div>
            <details className="g-rules"><summary>签到与积分规则</summary><p id="rules">登录后查看当前奖励规则。</p></details>
          </section>
        </div>
        <div className="g-tablist" role="tablist" aria-label="成长站分区">
          <button className="page-pill" id="tab-daily" role="tab" aria-controls="panel-daily" aria-selected="true" tabIndex={0} data-tab="daily"><BrandIcon name="star" size={17} />成长日常</button>
          <button className="page-pill" id="tab-wardrobe" role="tab" aria-controls="panel-wardrobe" aria-selected="false" tabIndex={-1} data-tab="wardrobe"><BrandIcon name="user" size={17} />装扮衣橱</button>
          <button className="page-pill" id="tab-wishes" role="tab" aria-controls="panel-wishes" aria-selected="false" tabIndex={-1} data-tab="wishes"><BrandIcon name="heart" size={17} />同好心愿</button>
          <button className="page-pill" id="tab-ledger" role="tab" aria-controls="panel-ledger" aria-selected="false" tabIndex={-1} data-tab="ledger"><BrandIcon name="history" size={17} />积分足迹</button>
        </div>
        <section id="panel-daily" className="g-panel" role="tabpanel" aria-labelledby="tab-daily">
          <div className="section-heading"><h2>日常里的小小成就 <span>DAILY SPARKS</span></h2><button id="refresh-growth" className="g-text-button" type="button"><BrandIcon name="history" size={15} />刷新进度</button></div>
          <p className="g-section-note">把故事看下去、收藏一份心动、留下你的声音。完成后，来领取属于你的奖励。</p>
          <div id="missions" className="g-missions"><p className="brand-empty">正在寻找今天的小目标…</p></div>
          <div className="g-story-note"><img src="/brand/bllii-symbol.svg" alt="" width={55} height={55} /><div><strong>热爱不必赶进度</strong><p>签到和任务奖励会积累成长值；消费不会降级，求片退款也不会重复增加成长值。</p></div><a href="/category" className="brand-outline">遇见下一部好故事 <BrandIcon name="arrow-right" size={15} /></a></div>
        </section>
        <section id="panel-wardrobe" className="g-panel" role="tabpanel" aria-labelledby="tab-wardrobe" hidden>
          <div className="section-heading"><h2>给热爱，添一点颜色 <span>YOUR LITTLE STYLE</span></h2><span className="g-muted" id="owned-count">装扮衣橱</span></div>
          <div id="shop-filters" className="g-filters" role="group" aria-label="装扮类型">
            {wardrobeFilters.map(([value, label]) => (
              <button key={value || 'all'} className="page-pill" type="button" data-filter={value} aria-pressed={value === '' ? 'true' : 'false'}>{label}</button>
            ))}
          </div>
          <p className="g-section-note">先试戴，看看和你的名字搭不搭。兑换后永久拥有，可以随时更换。</p>
          <div id="shop" className="g-shop-grid"><p className="brand-empty">正在打开衣橱…</p></div>
        </section>
        <section id="panel-wishes" className="g-panel" role="tabpanel" aria-labelledby="tab-wishes" hidden>
          <div className="g-wishes-layout"><div><div className="section-heading"><h2><span data-festival-copy="wishes-title">一起期待的故事</span> <span>WISH TOGETHER</span></h2><button id="refresh-wall" type="button" className="g-text-button">刷新</button></div><p className="g-section-note">给同好的心愿亮一盏灯，不消耗积分。每满 10 人亮灯，这部作品将被优先安排上架。</p><div id="wish-wall" className="g-wall"><p className="brand-empty">正在收集大家的期待…</p></div><div className="g-pagination"><button id="wall-prev" type="button" className="page-pill" disabled>上一页</button><span id="wall-page">第 1 页</span><button id="wall-next" type="button" className="page-pill" disabled>下一页</button></div></div>
            <aside className="g-request-box"><h2><BrandIcon name="library" size={20} />许一个观影心愿</h2><p id="request-rule">填写作品名与线索，管理员会通过站内消息回复。</p><form id="movie-request"><label htmlFor="request-title">想看的作品</label><input id="request-title" required maxLength={200} placeholder="一个名字，一份期待" /><label htmlFor="request-details">再给一点线索</label><textarea id="request-details" maxLength={2000} rows={3} placeholder="年份、主演、语言，或你记得的一个场景（选填）"></textarea><p className="g-privacy-note"><BrandIcon name="user" size={14} />默认仅你和管理员可见。提交后可主动公开，邀请同好助力。</p><button className="brand-button" id="submit-request" data-mutate type="submit" disabled>提交心愿 <BrandIcon name="arrow-right" size={16} /></button></form></aside>
          </div>
          <div className="section-heading g-own-heading"><h2>我的心愿进度</h2><a href="/notifications">查看处理消息 <BrandIcon name="arrow-right" size={14} /></a></div><div id="requests" className="g-requests"><p className="brand-empty">登录后查看你的心愿。</p></div><button id="requests-more" type="button" className="page-pill" hidden>加载更多心愿</button>
        </section>
        <section id="panel-ledger" className="g-panel" role="tabpanel" aria-labelledby="tab-ledger" hidden><div className="section-heading"><h2>每一点热爱，都有迹可循 <span>YOUR FOOTPRINTS</span></h2></div><p className="g-section-note">最近100笔奖励、消费与退款记录。可用积分用于兑换，成长值记录你的陪伴。</p><div id="ledger" className="g-ledger"><p className="brand-empty">登录后查看你的积分足迹。</p></div></section>
      </div>
    </Layout>
  );
}
