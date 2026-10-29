package webui

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAdminHandler(t *testing.T) {
	h := AdminHandler()
	req := httptest.NewRequest("GET", "/admin", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	body := rec.Body.String()
	if rec.Code != 200 || !strings.Contains(body, `<div id="app">`) {
		t.Fatalf("/admin -> %d, app mount = %v", rec.Code, strings.Contains(body, `<div id="app">`))
	}
}

func TestPortalHandlerSPAFallback(t *testing.T) {
	// 无 store：SSR 关闭，走 SPA 回退，外壳必须带 #root 挂载点
	h := PortalHandler(nil)
	req := httptest.NewRequest("GET", "/", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	body := rec.Body.String()
	if rec.Code != 200 || !strings.Contains(body, `<div id="root">`) {
		t.Fatalf("/ -> %d, root mount = %v", rec.Code, strings.Contains(body, `<div id="root">`))
	}

	// 静态资源直出
	req = httptest.NewRequest("GET", "/assets/client.css", nil)
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != 200 || !strings.Contains(rec.Body.String(), "brand-blue") {
		t.Fatalf("/assets/client.css -> %d", rec.Code)
	}
}

func TestPortalMovieRedirect(t *testing.T) {
	h := PortalHandler(nil)
	req := httptest.NewRequest("GET", "/movie", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != 302 {
		t.Fatalf("/movie -> %d, want 302", rec.Code)
	}
}
