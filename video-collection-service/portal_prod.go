//go:build !dev

// 生产态（默认构建）：门户走 go:embed 内嵌产物，见 web/embed.go。
package main

import (
	"net/http"

	"video-collection-service/pkg/store"
	webui "video-collection-service/web"
)

func newPortalHandler(dbStore store.Store) http.Handler {
	return webui.PortalHandler(dbStore)
}
