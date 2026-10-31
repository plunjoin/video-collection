// wf 构建引导：必须先于 main 执行（entry-client 第一条 import）。
//
// 1) Vue 特性标志：@vue/runtime-core 的产物以裸全局（__VUE_OPTIONS_API__ 等）引用
//    这三个开关，esbuild 不做 define 注入，webfront 构建也没有 vite 的 define 通道；
//    不在挂载前赋值，运行期会直接 ReferenceError。标志在模块求值期不被读取，
//    模块顶部赋值即可覆盖全部调用点。
// 2) 文档属性：wf 生成的 dist/index.html 只含 charset 与 #root 挂载点。
globalThis.__VUE_OPTIONS_API__ = true
globalThis.__VUE_PROD_DEVTOOLS__ = false
globalThis.__VUE_PROD_HYDRATION_MISMATCH_DETAILS__ = false

document.documentElement.lang = 'zh-CN'
document.title = '视频采集管理'

const viewport = document.createElement('meta')
viewport.name = 'viewport'
viewport.content = 'width=device-width, initial-scale=1.0'
document.head.appendChild(viewport)

const icon = document.createElement('link')
icon.rel = 'icon'
icon.type = 'image/svg+xml'
icon.href = '/brand/bllii-symbol.svg'
document.head.appendChild(icon)
