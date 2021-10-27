package m3u8cleaner

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
)

func TestCleanM3U8_HeadAd(t *testing.T) {
	rawM3U8 := `#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:3.000,
ad1.ts
#EXTINF:3.000,
ad2.ts
#EXT-X-DISCONTINUITY
#EXTINF:6.000,
movie1.ts
#EXTINF:6.000,
movie2.ts
#EXT-X-ENDLIST`

	opts := DefaultOptions()
	cleaned, err := CleanM3U8(rawM3U8, "https://cdn.example.com/video/index.m3u8", opts)
	if err != nil {
		t.Fatalf("CleanM3U8 failed: %v", err)
	}

	// 验证 ad1.ts 和 ad2.ts 是否被过滤
	if strings.Contains(cleaned, "ad1.ts") || strings.Contains(cleaned, "ad2.ts") {
		t.Errorf("expected head ad slices to be removed, got:\n%s", cleaned)
	}

	// 验证正片切片是否被保留，并且相对路径被补全为绝对路径
	expectedMovie1 := "https://cdn.example.com/video/movie1.ts"
	if !strings.Contains(cleaned, expectedMovie1) {
		t.Errorf("expected movie1 to be resolved to %s, got:\n%s", expectedMovie1, cleaned)
	}

	// 验证 MEDIA-SEQUENCE 是否更新为 2
	if !strings.Contains(cleaned, "#EXT-X-MEDIA-SEQUENCE:2") {
		t.Errorf("expected media sequence updated to 2, got:\n%s", cleaned)
	}

	// 验证开头的 DISCONTINUITY 是否被清洗掉（因为片头已删，正片直接作为第一组）
	if strings.Contains(cleaned, "#EXT-X-DISCONTINUITY") {
		t.Errorf("expected leading discontinuity removed after head ad deletion, got:\n%s", cleaned)
	}
}

func TestCleanM3U8_KeywordFilter(t *testing.T) {
	rawM3U8 := `#EXTM3U
#EXT-X-VERSION:3
#EXTINF:6.000,
https://normal.com/movie1.ts
#EXTINF:5.000,
https://ad.domain.com/guanggao_01.ts
#EXTINF:6.000,
https://normal.com/movie2.ts
#EXT-X-ENDLIST`

	opts := DefaultOptions()
	cleaned, err := CleanM3U8(rawM3U8, "https://normal.com/index.m3u8", opts)
	if err != nil {
		t.Fatalf("CleanM3U8 failed: %v", err)
	}

	if strings.Contains(cleaned, "guanggao_01.ts") {
		t.Errorf("expected blacklisted keyword ad to be removed, got:\n%s", cleaned)
	}
	if !strings.Contains(cleaned, "movie1.ts") || !strings.Contains(cleaned, "movie2.ts") {
		t.Errorf("expected normal movies preserved, got:\n%s", cleaned)
	}
}

func TestCleanM3U8_KeyResolution(t *testing.T) {
	rawM3U8 := `#EXTM3U
#EXT-X-VERSION:3
#EXT-X-KEY:METHOD=AES-128,URI="enc.key",IV=0x123456
#EXTINF:6.000,
movie1.ts
#EXT-X-ENDLIST`

	opts := DefaultOptions()
	cleaned, err := CleanM3U8(rawM3U8, "https://cdn.example.com/ep1/index.m3u8", opts)
	if err != nil {
		t.Fatalf("CleanM3U8 failed: %v", err)
	}

	expectedKey := `URI="https://cdn.example.com/ep1/enc.key"`
	if !strings.Contains(cleaned, expectedKey) {
		t.Errorf("expected key URI resolved to %s, got:\n%s", expectedKey, cleaned)
	}
}

func TestCleanM3U8_MasterPlaylist(t *testing.T) {
	rawM3U8 := `#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1920x1080
1080p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720
720p/index.m3u8`

	opts := DefaultOptions()
	opts.ProxyBaseURL = "/api/m3u8/clean"
	cleaned, err := CleanM3U8(rawM3U8, "https://cdn.example.com/stream/master.m3u8", opts)
	if err != nil {
		t.Fatalf("CleanM3U8 failed: %v", err)
	}

	if !strings.Contains(cleaned, "/api/m3u8/clean?url=https%3A%2F%2Fcdn.example.com%2Fstream%2F1080p%2Findex.m3u8") {
		t.Errorf("expected 1080p stream rewritten to proxy url, got:\n%s", cleaned)
	}
}

func TestHandler_ServeHTTP(t *testing.T) {
	// 创建模拟上游服务器
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
		_, _ = w.Write([]byte("#EXTM3U\n#EXTINF:5.000,\n001.ts\n#EXT-X-ENDLIST"))
	}))
	defer upstream.Close()

	handler := NewHandler(DefaultOptions())

	// 1. 测试标准 encoded url 请求，不应报 400
	req := httptest.NewRequest(http.MethodGet, "/api/m3u8/clean?url="+url.QueryEscape(upstream.URL+"/index.m3u8"), nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d, body: %s", rec.Code, rec.Body.String())
	}

	if !strings.Contains(rec.Body.String(), upstream.URL+"/001.ts") {
		t.Fatalf("expected resolved ts path in output, got: %s", rec.Body.String())
	}

	// 2. 测试缺少 url 参数报错 400
	reqMissing := httptest.NewRequest(http.MethodGet, "/api/m3u8/clean", nil)
	recMissing := httptest.NewRecorder()
	handler.ServeHTTP(recMissing, reqMissing)
	if recMissing.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400 for missing url, got %d", recMissing.Code)
	}
}

func TestCleanM3U8_SequenceOutlier(t *testing.T) {
	// 真实资源站结构：正片 000072, 000073，插播广告 0033175 ~ 0033181，回归正片 000074
	rawM3U8 := `#EXTM3U
#EXT-X-VERSION:3
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-TARGETDURATION:8
#EXT-X-DISCONTINUITY
#EXTINF:4.560,
825e24e3d9e0000072.ts
#EXTINF:4.560,
825e24e3d9e0000073.ts
#EXT-X-DISCONTINUITY
#EXTINF:4.000,
825e24e3d9e0033175.ts
#EXTINF:4.000,
825e24e3d9e0033176.ts
#EXTINF:4.000,
825e24e3d9e0033177.ts
#EXTINF:4.000,
825e24e3d9e0033178.ts
#EXTINF:4.000,
825e24e3d9e0033179.ts
#EXTINF:4.000,
825e24e3d9e0033180.ts
#EXTINF:1.700,
825e24e3d9e0033181.ts
#EXT-X-DISCONTINUITY
#EXTINF:3.600,
825e24e3d9e0000074.ts
#EXT-X-ENDLIST`

	opts := DefaultOptions()
	cleaned, err := CleanM3U8(rawM3U8, "https://v.lzcdn31.com/20260807/9490_7c54ec6a/2000k/hls/mixed.m3u8", opts)
	if err != nil {
		t.Fatalf("CleanM3U8 failed: %v", err)
	}

	// 1. 验证广告片段 33175 ~ 33181 全部被剔除
	if strings.Contains(cleaned, "0033175.ts") || strings.Contains(cleaned, "0033181.ts") {
		t.Fatalf("expected middle ad slices to be removed, got:\n%s", cleaned)
	}

	// 2. 验证正片切片 72, 73, 74 全部被保留并补全绝对路径
	if !strings.Contains(cleaned, "825e24e3d9e0000072.ts") || !strings.Contains(cleaned, "825e24e3d9e0000074.ts") {
		t.Fatalf("expected feature video slices to be preserved, got:\n%s", cleaned)
	}

	// 3. 验证 73 与 74 之间原本多余的广告 DISCONTINUITY 已被平滑消除
	// 期望只在最开头保留一个，或者中间广告被抹掉后 73 和 74 之间没有 DISCONTINUITY
	lines := strings.Split(cleaned, "\n")
	foundBetween := false
	for i := 0; i < len(lines)-1; i++ {
		if strings.Contains(lines[i], "0000073.ts") && strings.Contains(lines[i+1], "#EXT-X-DISCONTINUITY") {
			foundBetween = true
			break
		}
	}
	if foundBetween {
		t.Fatalf("expected discontinuity between continuous movie slices 73 and 74 to be removed, got:\n%s", cleaned)
	}
}

func TestCleanM3U8_WithRealFile(t *testing.T) {
	// 读取下载的真实资源站 m3u8 文件
	rawBytes, err := os.ReadFile("testdata/real_mixed.m3u8")
	if err != nil {
		t.Skip("testdata/real_mixed.m3u8 not found, skipping file test")
		return
	}

	opts := DefaultOptions()
	cleaned, err := CleanM3U8(string(rawBytes), "https://v.lzcdn31.com/20260807/9490_7c54ec6a/2000k/hls/mixed.m3u8", opts)
	if err != nil {
		t.Fatalf("CleanM3U8 failed: %v", err)
	}

	// 验证 33175 ~ 33181 广告切片是否全部被清除
	for i := 33175; i <= 33181; i++ {
		targetAd := fmt.Sprintf("%d.ts", i)
		if strings.Contains(cleaned, targetAd) {
			t.Fatalf("real ad slice %s still exists in cleaned m3u8!", targetAd)
		}
	}

	// 验证正片首个切片 000000 和 最后一个切片 0000074 均完整存在
	if !strings.Contains(cleaned, "825e24e3d9e000000.ts") {
		t.Fatal("first movie slice 000000 missing!")
	}
	if !strings.Contains(cleaned, "825e24e3d9e000074.ts") {
		t.Fatal("last movie slice 000074 missing!")
	}

	// 验证正片所有相对路径均被补全为 https://v.lzcdn31.com 绝对路径
	if !strings.Contains(cleaned, "https://v.lzcdn31.com/20260807/9490_7c54ec6a/2000k/hls/825e24e3d9e000000.ts") {
		t.Fatal("relative path not resolved to absolute URL!")
	}
}

