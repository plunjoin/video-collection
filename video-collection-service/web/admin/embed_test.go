package admin

import (
	"io/fs"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestSPAHandler(t *testing.T) {
	h := Handler()
	cases := []struct {
		path       string
		wantCode   int
		wantInBody string
	}{
		{"/admin", 200, "<div id=\"app\""},
		{"/admin/", 200, "<div id=\"app\""},
		{"/admin/dashboard", 200, "<div id=\"app\""},
		{"/admin/videos?page=2", 200, "<div id=\"app\""},
	}
	for _, c := range cases {
		req := httptest.NewRequest("GET", c.path, nil)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		body := rec.Body.String()
		// 接受两种合法产物：前端已构建（app 挂载点）或占位页（提示构建，随仓库发布）
		okBody := strings.Contains(body, c.wantInBody) || strings.Contains(body, "admin-build-required")
		if rec.Code != c.wantCode || !okBody {
			t.Errorf("%s -> %d, body=%q", c.path, rec.Code, body[:min(120, len(body))])
		} else {
			t.Logf("%s -> %d OK", c.path, rec.Code)
		}
	}

	// 静态资源应命中带哈希的 assets（长缓存 + 实际文件内容）
	aReq := httptest.NewRequest("GET", "/admin/assets/"+firstAssetName(t), nil)
	aRec := httptest.NewRecorder()
	h.ServeHTTP(aRec, aReq)
	if aRec.Code != 200 || aRec.Body.Len() == 0 {
		t.Errorf("静态资源 %s -> %d", aReq.URL.Path, aRec.Code)
	} else {
		t.Logf("%s -> %d (%d bytes)", aReq.URL.Path, aRec.Code, aRec.Body.Len())
	}
}

// firstAssetName 返回内嵌 dist 中的任意一个 assets 文件名
func firstAssetName(t *testing.T) string {
	t.Helper()
	entries, err := fs.ReadDir(mustSub(t), "assets")
	if err != nil || len(entries) == 0 {
		t.Fatalf("读取内嵌 assets 失败: %v", err)
	}
	return entries[0].Name()
}

func mustSub(t *testing.T) fs.FS {
	t.Helper()
	sub, err := fs.Sub(files, "dist")
	if err != nil {
		t.Fatalf("fs.Sub 失败: %v", err)
	}
	return sub
}
