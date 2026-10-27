'use strict';

// Presentation only: no filesystem, installer, launcher, or deletion APIs are used.
const $ = (selector) => document.querySelector(selector);
const icon = (name) => `<svg aria-hidden="true"><use href="#icon-${name}"/></svg>`;
const assets = '../../../bllii-brand-kit';
const state = { flow: 'install', screen: 'welcome', progress: 0, path: 'C:\\Users\\用户名\\AppData\\Local\\Programs\\Bllii', desktop: true, launch: true, data: 'keep' };
let progressTimer;
let toastTimer;
const scenes = {
  install: [['welcome', '准备安装'], ['progress', '安装中'], ['success', '安装完成'], ['error', '异常状态']],
  uninstall: [['welcome', '卸载确认'], ['progress', '卸载中'], ['success', '卸载完成'], ['error', '异常状态']],
};
const escapeHTML = (value) => String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
function notify(message) {
  clearTimeout(toastTimer);
  $('#toast').textContent = message;
  $('#toast').hidden = false;
  toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 4500);
}
function dialog(title, body, actions) {
  $('#modal-content').innerHTML = `<h2 id="modal-title">${title}</h2>${body}`;
  $('#modal-actions').innerHTML = actions.map((item, i) => `<button type="button" class="button ${item.className || ''}" data-modal-action="${i}">${item.label}</button>`).join('');
  $('#modal-actions').querySelectorAll('button').forEach((button, i) => button.addEventListener('click', () => actions[i].action()));
  $('#modal').showModal();
}
const dismiss = () => $('#modal').close();
function validatePath(path) {
  return /^[a-z]:\\[^<>:"/|?*\x00-\x1f]+$/i.test(path.trim()) && !path.split('\\').slice(1).some(part => !part || /[. ]$/.test(part) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)/i.test(part));
}
function showPathError() {
  const field = $('#install-path');
  if (!field) return false;
  const invalid = !validatePath(field.value);
  field.setAttribute('aria-invalid', String(invalid));
  $('.path-field').classList.toggle('invalid', invalid);
  $('#path-error').hidden = !invalid;
  if (invalid) field.focus();
  else state.path = field.value.trim();
  return !invalid;
}
function chooseFolder() {
  dialog('选择安装位置', '<p>输入一个 Windows 文件夹路径，预览安装位置。</p><label for="folder-path">安装目录<input id="folder-path" autocomplete="off" spellcheck="false"></label><p id="folder-error" class="field-error" role="alert" hidden>请输入有效的绝对路径，例如 D:\\Apps\\Bllii。</p>', [
    { label: '取消', action: dismiss },
    { label: '使用此位置', className: 'primary', action: () => {
      if (!validatePath($('#folder-path').value)) { $('#folder-error').hidden = false; $('#folder-path').focus(); return; }
      state.path = $('#folder-path').value.trim(); dismiss(); render();
    } },
  ]);
  $('#folder-path').value = state.path;
  $('#folder-path').focus();
}
function requestClose() {
  if (state.screen === 'progress') { notify('正在处理文件，请等待当前步骤完成。'); return; }
  if (state.screen === 'closed') return;
  if (state.screen === 'success') { setScreen('closed'); return; }
  const installing = state.flow === 'install';
  dialog(installing ? '暂时不安装？' : '取消卸载？', `<p>${installing ? '关闭安装向导后，你可以随时重新开始。' : 'Bllii 会继续留在你的电脑上。'}</p>`, [
    { label: '继续' + (installing ? '安装' : '卸载'), action: dismiss },
    { label: installing ? '退出安装' : '保留 Bllii', className: 'primary', action: () => { dismiss(); setScreen('closed'); } },
  ]);
}
function startProgress() { setScreen('progress', true); }
function beginUninstall() {
  if (state.data === 'keep') { startProgress(); return; }
  dialog('同时清除本地数据？', '<p>本地设置、登录状态和观看记录将一并删除。此操作无法撤销。</p>', [
    { label: '返回', action: dismiss },
    { label: '清除并卸载', className: 'danger', action: () => { dismiss(); startProgress(); } },
  ]);
}
function heading(kicker, title, description) {
  return `<p class="step-label">${kicker}</p><h2 class="screen-heading">${title}</h2><p class="screen-description">${description}</p>`;
}
function welcome() {
  if (state.flow === 'uninstall') return `${heading('UNTIL THE NEXT STORY', '和 Bllii 暂别一下。', '谢谢你，让 Bllii 陪你度过一段好时光。')}
    <div class="uninstall-summary"><img src="${assets}/svg/bllii-app-light.svg" alt=""><div><strong>Bllii 桌面客户端</strong><p>版本 1.0.1 · Windows x64</p></div></div>
    <fieldset class="data-options"><legend>卸载时，如何处理本地数据？</legend><label class="radio-option"><input type="radio" name="data" value="keep" ${state.data === 'keep' ? 'checked' : ''}><span><strong>保留本地数据 <small class="recommended">推荐</small></strong><small>保留设置与观看记录，下次安装时继续使用。</small></span></label><label class="radio-option"><input type="radio" name="data" value="remove" ${state.data === 'remove' ? 'checked' : ''}><span><strong>同时清除本地数据</strong><small>删除这台电脑上的设置、登录状态与观看记录。</small></span></label></fieldset>
    <div class="cta-block"><div class="uninstall-cta"><button type="button" class="button secondary" id="keep-app">先留下吧</button><button type="button" class="button primary" id="uninstall">确认卸载 ${icon('arrow')}</button></div><p class="cta-note">仅处理此电脑上的应用与所选本地数据</p></div>`;
  return `${heading('HELLO, NEW STORIES', '把精彩，装进桌面。', '欢迎使用 Bllii。只需一步，就能开启新的故事。')}
    <div class="version-line"><span class="version-tag">${icon('desktop')} Windows x64</span><span class="separator"></span><span>版本 1.0.1</span></div>
    <div class="install-options"><label for="install-path" class="field-label">安装位置 <span>可自定义目录</span></label><div class="path-field">${icon('folder')}<input id="install-path" aria-describedby="path-error" spellcheck="false" autocomplete="off" value="${escapeHTML(state.path)}"><button type="button" id="browse">更改</button></div><p id="path-error" class="field-error" role="alert" hidden>请输入有效的 Windows 路径，例如 D:\\Apps\\Bllii。</p>
    <div class="check-options"><label class="check-option"><input id="desktop" type="checkbox" ${state.desktop ? 'checked' : ''}>创建桌面快捷方式</label><label class="check-option"><input id="launch" type="checkbox" ${state.launch ? 'checked' : ''}>安装后启动 Bllii</label></div></div>
    <div class="cta-block"><button type="button" class="button primary full-width" id="install">安装 Bllii ${icon('arrow')}</button><p class="cta-note">安装后可在 Windows 设置中随时卸载</p></div>`;
}
function progress() {
  const installing = state.flow === 'install';
  return `${heading(installing ? 'GETTING EVERYTHING READY' : 'TAKING CARE OF THE DETAILS', installing ? '好故事，即将开场。' : '正在轻轻地告别。', installing ? '正在为你准备桌面上的新伙伴，请稍候。' : '正在移除应用文件，请保持窗口开启。')}
    <div class="progress-art"><img src="${assets}/animation/bllii-loading.svg" alt=""></div>
    <div class="progress-heading"><span id="progress-caption"></span><strong id="percentage"></strong></div><div class="progress-track" role="progressbar" aria-label="${installing ? '安装' : '卸载'}进度" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><div class="progress-fill"></div></div><div class="progress-detail"><span id="file-detail"></span><span>请稍候</span></div><div class="progress-steps"></div>
    <div class="progress-actions"><span class="cta-note">${installing ? '精彩正在路上，马上就好。' : state.data === 'keep' ? '你的本地数据会被妥善保留。' : '正在按你的选择清除本地数据。'}</span></div>`;
}
function success() {
  const installing = state.flow === 'install';
  return `${heading(installing ? 'READY FOR YOUR NEXT STORY' : 'THANK YOU FOR THE GOOD TIMES', installing ? '准备好了，开场吧！' : '已卸载，后会有期。', installing ? 'Bllii 已准备就绪，新的故事正等着你。' : 'Bllii 已从这台电脑移除。谢谢你曾经的陪伴。')}
    <div class="progress-art success-art"><img src="${assets}/svg/bllii-symbol.svg" alt=""><span class="status-badge">${icon('check')}</span></div>
    <div class="success-note">${icon(installing ? 'desktop' : state.data === 'keep' ? 'folder' : 'check')}<div><strong>${installing ? state.desktop ? '桌面见，我们的故事继续。' : '下一段精彩，随时开启。' : state.data === 'keep' ? '本地数据已保留' : '本地数据已清除'}</strong><p>${installing ? state.desktop ? '双击桌面上的 Bllii，即可再次打开。' : '可以从开始菜单打开 Bllii。' : state.data === 'keep' ? '下次安装时，可继续使用原有设置与观看记录。' : '此电脑上的设置、登录状态与观看记录已删除。'}</p></div></div>
    <div class="cta-block"><button type="button" class="button primary full-width" id="finish">${installing ? state.launch ? '开启 Bllii' : '完成安装' : '完成卸载'} ${icon(installing && state.launch ? 'arrow' : 'check')}</button><p class="cta-note">${installing ? 'More Stories, Together' : '愿你的下一个故事，同样精彩。'}</p></div>`;
}
function errorScreen() {
  const installing = state.flow === 'install';
  return `${heading('LET’S TRY THAT AGAIN', installing ? '安装遇到一点小插曲。' : '暂时还不能完成卸载。', '不用着急，处理后可以继续。')}
    <div class="error-callout">${icon('info')}<div><strong>${installing ? '暂时无法写入安装目录' : 'Bllii 的部分文件正在使用中'}</strong><p>${installing ? '请检查文件夹的写入权限，或更换一个安装位置。' : '请先关闭正在运行的 Bllii，再重试卸载。'}</p></div></div>
    <ol class="error-steps"><li>${installing ? '确认所选磁盘有足够的可用空间。' : '保存当前进度，并退出 Bllii。'}</li><li>${installing ? '关闭占用安装文件夹的应用后重试。' : '关闭可能占用应用文件的其他窗口。'}</li></ol>
    <div class="cta-block"><div class="uninstall-cta"><button type="button" class="button secondary" id="back">${installing ? '更改位置' : '返回'}</button><button type="button" class="button primary" id="retry">重试${installing ? '安装' : '卸载'} ${icon('arrow')}</button></div><p class="cta-note">${installing ? '你的安装选项已保留' : '卸载选项已保留，可以稍后继续'}</p></div>`;
}
function updateProgress() {
  const installing = state.flow === 'install';
  const p = state.progress;
  const stages = installing ? ['准备文件', '安装应用', '完成配置'] : ['检查应用', '移除文件', state.data === 'keep' ? '保留数据' : '清理数据'];
  const active = p < 20 ? 0 : p < 85 ? 1 : 2;
  $('#percentage').textContent = `${p}%`;
  $('.progress-fill').style.width = `${p}%`;
  $('.progress-track').setAttribute('aria-valuenow', String(p));
  $('#progress-caption').textContent = (installing ? ['正在准备安装文件', '正在安装 Bllii', '正在完成最后的配置'] : ['正在检查运行状态', '正在移除应用文件', state.data === 'keep' ? '正在保留本地数据' : '正在清除本地数据'])[active];
  $('#file-detail').textContent = (installing ? ['准备安装目录', '正在写入客户端文件', '正在配置应用入口'] : ['检查应用文件', '正在移除客户端文件', state.data === 'keep' ? '保留设置与观看记录' : '清理设置与观看记录'])[active];
  $('.progress-steps').innerHTML = stages.map((text, index) => `<span class="${index <= active ? 'done' : ''}">${icon(index < active ? 'check' : 'desktop')} ${text}</span>`).join('');
}
function render() {
  const installing = state.flow === 'install';
  $('.installer-window').classList.toggle('uninstall-flow', !installing);
  $('#window-title').textContent = `Bllii ${installing ? '安装' : '卸载'}程序`;
  $('#brand-heading').innerHTML = installing ? '让每个故事，<br>生动一点。' : '故事有暂停，<br>热爱不散场。';
  $('#brand-description').textContent = installing ? '把热爱留在身边，把精彩交给 Bllii。' : '每一次相遇，都值得好好说再见。';
  $('#footer-label').textContent = installing ? '为当前用户安装' : '尊重你的每一次选择';
  document.querySelectorAll('[data-flow]').forEach(button => {
    const active = button.dataset.flow === state.flow;
    button.classList.toggle('active', active); button.setAttribute('aria-pressed', String(active));
  });
  $('.state-switch').innerHTML = scenes[state.flow].map(([screen, title]) => `<button type="button" data-screen="${screen}" class="${state.screen === screen ? 'active' : ''}" aria-pressed="${state.screen === screen}">${title}</button>`).join('');
  $('.state-switch').querySelectorAll('button').forEach(button => button.addEventListener('click', () => setScreen(button.dataset.screen)));
  $('#screen').innerHTML = state.screen === 'welcome' ? welcome() : state.screen === 'progress' ? progress() : state.screen === 'success' ? success() : state.screen === 'error' ? errorScreen() : `<div class="closed-screen"><img src="${assets}/svg/bllii-horizontal.svg" alt="bllii"><h2>我们下个故事见。</h2><p>向导已关闭，你可以重新体验整个流程。</p><button class="button primary" type="button" id="restart">重新预览 ${icon('arrow')}</button></div>`;
  if (state.screen === 'progress') updateProgress();
  const on = (selector, event, handler) => { const target = $(selector); if (target) target.addEventListener(event, handler); };
  on('#browse', 'click', chooseFolder);
  on('#install-path', 'input', event => { state.path = event.target.value; });
  on('#desktop', 'change', event => { state.desktop = event.target.checked; });
  on('#launch', 'change', event => { state.launch = event.target.checked; });
  on('#install', 'click', () => { if (showPathError()) startProgress(); });
  on('#uninstall', 'click', beginUninstall);
  on('#keep-app', 'click', () => { notify('已取消卸载，Bllii 继续陪伴你。'); setScreen('closed'); });
  on('#finish', 'click', () => { if (installing && state.launch) notify('预览演示：实际安装完成后，此处将启动 Bllii。'); setScreen('closed'); });
  on('#restart', 'click', () => setScreen('welcome'));
  on('#back', 'click', () => setScreen('welcome'));
  on('#retry', 'click', () => installing ? startProgress() : beginUninstall());
  document.querySelectorAll('input[name="data"]').forEach(input => input.addEventListener('change', () => { state.data = input.value; }));
}
function setScreen(screen, animate = false) {
  clearInterval(progressTimer);
  $('#modal').close();
  $('.minimized-overlay').hidden = true;
  state.screen = screen;
  state.progress = animate ? 0 : 56;
  render();
  if (screen === 'progress' && animate) progressTimer = setInterval(() => {
    state.progress = Math.min(100, state.progress + (state.progress < 75 ? 4 : 2));
    updateProgress();
    if (state.progress === 100) setScreen('success');
  }, 240);
}
document.querySelectorAll('[data-flow]').forEach(button => button.addEventListener('click', () => { state.flow = button.dataset.flow; setScreen('welcome'); }));
$('#close-window').addEventListener('click', requestClose);
$('#minimize').addEventListener('click', () => { $('.minimized-overlay').hidden = false; });
$('#restore-window').addEventListener('click', () => { $('.minimized-overlay').hidden = true; });
// Enter submits the folder picker, while Escape uses the native dialog dismissal.
$('#modal form').addEventListener('submit', event => {
  event.preventDefault();
  $('#modal-actions button:last-child')?.click();
});
const requestedFlow = new URLSearchParams(location.search).get('flow');
if (requestedFlow === 'uninstall') state.flow = requestedFlow;
const requestedScreen = new URLSearchParams(location.search).get('screen');
if (scenes[state.flow].some(([screen]) => screen === requestedScreen)) state.screen = requestedScreen;
state.progress = 56;
render();
