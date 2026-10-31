// wf 构建引导（Vue 特性标志 + 文档属性）：entry-client 与 main 都引它，
// ES module 语义下只执行一次，且必须先于后续依赖求值。
import './bootstrap'
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { RadixUiPlugin } from './components/radix'
import { iconAliases } from './components/radix/icons'
// 基础组件样式静态打包（原 RadixUiPlugin 运行时注入，缓存/CSP 场景可能不生效）
import './styles/radix-base.css'
import './styles/index.css'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)
app.use(RadixUiPlugin)

for (const [name, component] of Object.entries(iconAliases)) {
  app.component(name, component)
}

app.mount('#root')
