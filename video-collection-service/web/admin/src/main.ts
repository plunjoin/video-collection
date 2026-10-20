import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { RadixUiPlugin } from './components/radix'
import { iconAliases } from './components/radix/icons'
// 基础组件样式静态打包（原 RadixUiPlugin 运行时注入，缓存/CSP 场景可能不生效）
import './styles/radix-base.css'
import './styles/index.scss'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)
app.use(RadixUiPlugin)

for (const [name, component] of Object.entries(iconAliases)) {
  app.component(name, component)
}

app.mount('#app')
