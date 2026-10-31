//go:build !dev

// 管理后台生产接线：内嵌产物托管（web/admin/dist 经 go:embed 烧入二进制）。
// dev 构建走 admin_dev.go 的 webfront DevServer（/admin 也支持 HMR）。
package main

import (
	"net/http"

	webui "video-collection-service/web"
)

func newAdminHandler() http.Handler {
	return webui.AdminHandler()
}
