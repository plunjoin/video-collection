package api

import (
	"net/http"
	"video-collection-api/config"
)

func (srv *Server) handleCollectionTemplates(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	templates, err := config.LoadCollectionTemplates()
	if err != nil {
		errorResponse(w, 500, "读取采集规则模板失败: "+err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": templates})
}
