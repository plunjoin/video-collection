import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { RadixUiPlugin } from './components/radix'
import { iconAliases } from './components/radix/icons'
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
