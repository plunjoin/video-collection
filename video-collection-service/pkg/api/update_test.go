package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAppUpdateEndpoint(t *testing.T) {
	f := newContentFixture(t)

	// Test 1: Default configuration
	req := httptest.NewRequest(http.MethodGet, "/api/app/latest?platform=android&version=0.9.0", nil)
	rec := httptest.NewRecorder()
	f.mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	var res struct {
		Code int `json:"code"`
		Data struct {
			Version     string            `json:"version"`
			VersionCode int               `json:"version_code"`
			Title       string            `json:"title"`
			Changelog   string            `json:"changelog"`
			ForceUpdate bool              `json:"force_update"`
			DownloadURL string            `json:"download_url"`
			Platforms   map[string]string `json:"platforms"`
			HasUpdate   bool              `json:"has_update"`
		} `json:"data"`
	}

	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if res.Code != 1 {
		t.Fatalf("expected code 1, got %d", res.Code)
	}
	if res.Data.Version != "1.0.0" {
		t.Errorf("expected version 1.0.0, got %s", res.Data.Version)
	}
	if !res.Data.HasUpdate {
		t.Errorf("expected has_update=true for version 0.9.0, got false")
	}
	if res.Data.Platforms["android"] == "" {
		t.Errorf("expected android platform download url to be present")
	}
	if res.Data.DownloadURL != res.Data.Platforms["android"] {
		t.Errorf("expected download_url to match android platform url, got %s", res.Data.DownloadURL)
	}

	// Test 2: When client is on latest or newer version
	reqSame := httptest.NewRequest(http.MethodGet, "/api/app/latest?platform=windows&version=1.0.0", nil)
	recSame := httptest.NewRecorder()
	f.mux.ServeHTTP(recSame, reqSame)

	var resSame struct {
		Code int `json:"code"`
		Data struct {
			HasUpdate   bool   `json:"has_update"`
			DownloadURL string `json:"download_url"`
		} `json:"data"`
	}
	_ = json.Unmarshal(recSame.Body.Bytes(), &resSame)
	if resSame.Data.HasUpdate {
		t.Errorf("expected has_update=false for version 1.0.0, got true")
	}

	// Test 3: Custom settings override
	_ = f.s.SetSettings(context.Background(), map[string]string{
		"app_latest_version": "1.2.0",
		"app_changelog":      "新的特性上线啦",
		"app_force_update":   "1",
		"app_android_url":    "https://cdn.example.com/bllii_v1.2.0.apk",
	})

	reqUpdated := httptest.NewRequest(http.MethodGet, "/api/app/latest?platform=android&version=1.0.0", nil)
	recUpdated := httptest.NewRecorder()
	f.mux.ServeHTTP(recUpdated, reqUpdated)

	var resUpdated struct {
		Code int `json:"code"`
		Data struct {
			Version     string `json:"version"`
			Changelog   string `json:"changelog"`
			ForceUpdate bool   `json:"force_update"`
			DownloadURL string `json:"download_url"`
			HasUpdate   bool   `json:"has_update"`
		} `json:"data"`
	}
	_ = json.Unmarshal(recUpdated.Body.Bytes(), &resUpdated)
	if resUpdated.Data.Version != "1.2.0" {
		t.Errorf("expected version 1.2.0, got %s", resUpdated.Data.Version)
	}
	if !resUpdated.Data.HasUpdate {
		t.Errorf("expected has_update=true, got false")
	}
	if !resUpdated.Data.ForceUpdate {
		t.Errorf("expected force_update=true, got false")
	}
	if resUpdated.Data.DownloadURL != "https://cdn.example.com/bllii_v1.2.0.apk" {
		t.Errorf("expected custom download url, got %s", resUpdated.Data.DownloadURL)
	}
}

func TestCompareSemver(t *testing.T) {
	cases := []struct {
		v1, v2 string
		want   int
	}{
		{"1.0.0", "1.0.0", 0},
		{"v1.0.0", "1.0.0", 0},
		{"1.0.1", "1.0.0", 1},
		{"1.0.0", "1.0.1", -1},
		{"1.1.0", "1.0.9", 1},
		{"2.0.0", "1.9.9", 1},
		{"1.0.0+2", "1.0.0+1", 1},
		{"1.0.0+1", "1.0.0+2", -1},
		{"1.0.0+1", "1.0.0+1", 0},
		{"v1.2.3", "v1.2.3", 0},
		{"1.2", "1.2.0", 0},
	}

	for _, tc := range cases {
		got := compareSemver(tc.v1, tc.v2)
		if got != tc.want {
			t.Errorf("compareSemver(%q, %q) = %d, want %d", tc.v1, tc.v2, got, tc.want)
		}
	}
}
