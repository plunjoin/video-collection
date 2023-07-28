package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestM3U8ProxyRoutesRemoved(t *testing.T) {
	mux := http.NewServeMux()
	NewServer(nil, nil, nil, nil).RegisterRoutes(mux)
	for _, path := range []string{"/api/m3u8", "/api/m3u8/clean"} {
		for _, method := range []string{http.MethodGet, http.MethodOptions} {
			rec := httptest.NewRecorder()
			mux.ServeHTTP(rec, httptest.NewRequest(method, path+"?url=https%3A%2F%2Fexample.com%2Findex.m3u8", nil))
			if rec.Code != http.StatusNotFound {
				t.Fatalf("%s %s: status=%d, want 404", method, path, rec.Code)
			}
		}
	}
}
