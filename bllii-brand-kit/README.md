# bllii 品牌资产

基于提供的参考位图手工重绘，品牌拼写已确认：bllii。此包是优化后的矢量重绘，并非从原设计源文件导出。

## 文件
- svg/：独立图形、字标、横版、竖版、黑白单色、4 种 App 图标。标志与字标均为矢量路径；无外链图片或字体依赖。
- components/：同坐标系的播放外壳、速度短线、面部，叠加即可恢复图形。字标单独提供。
- png/：透明 PNG；App 图标为有底色版本。
- animation/bllii-loading.svg：1.8 秒运动循环，3.6 秒表情循环，透明背景。
- animation/bllii-loading.gif：白底通用预览，GIF 不适合高质量透明边缘。
- animation/bllii-intro.svg：开场 2.4 秒完成入场，最终完整标志持续停留；透明背景。
- animation/bllii-intro.mp4：1920×1080 / 30 fps / 4 秒 / 白底 / 无音轨。
- animation/*-demo.html：可离线打开的动画示例。
- index.html：离线资产与动画预览，可重播、切换背景、暂停动画。

## 设计规则
蓝 #4B9FFF / 紫 #9A83FF / 粉 #FF89C7 / 深墨 #353B58。
保留原图中的圆润播放轮廓、速度短线、倾斜表情和双彩色圆点；统一了字标笔画与圆角，清除了位图光晕和不规则高光。内腔为真正镂空，不是白色覆盖。
推荐图形最小显示宽度 32px，含完整面部时优先 48px 以上。横版组合最小宽度 140px；标志四周至少留出图形高度约 1/8 的空白。更小的 favicon 应按实际终端单独做像素优化。
App 的圆角版用于展示；fullbleed 方形版用于由平台施加圆角的场景。
原参考中的多套小字口号属于应用展示，本次沿用主口号 More Stories, Together 作为开场文案；口号为可编辑文本，字体使用 Arial / sans-serif。

## 网页接入
功能图标新增 `svg/bllii-ui.svg`：42 个 24×24 图标，涵盖导航、搜索、收藏、社区和播放器。延续圆润外壳、速度短线与粉色点缀，主笔画继承 `currentColor`，推荐 16–28px 显示。通过 `<svg ...><use href="bllii-ui.svg#bllii-play" /></svg>` 使用；播放器内嵌同一套图标以兼容独立部署。
图标总览：`ui-icons.html`。修改图标后，在 web 目录运行 `npm run brand:sync`，同步网页素材与 web/API 两份播放器。

加载图可用 <img src="bllii-loading.svg" width="80" alt="正在加载">。SVG 内置 CSS；多数现代浏览器支持，部分设计软件只显示静态图。SVG 可导入 Figma / Illustrator 继续编辑，CSS 动画不等同于这些软件的原生时间线。
开场 SVG 播放一次后停留；若要自动进入业务界面，在宿主应用处理完成事件或定时切换。预览按钮只用于演示。动画尊重 prefers-reduced-motion 设置；GIF / MP4 为固定媒体，请由宿主决定是否播放。
本包不含 Lottie JSON、原生 .ai 文件或音效。
