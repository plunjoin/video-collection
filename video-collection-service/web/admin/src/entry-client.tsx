// wf 构建入口（wf build 固定优先探测 src/entry-client.tsx）。
// bootstrap 必须先于 main 求值：ES module 的 import 按声明顺序执行。
import './bootstrap'
import './main'
