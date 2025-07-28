package m3u8cleaner

import (
	"crypto/tls"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type cacheEntry struct {
	content   string
	expiredAt time.Time
}

// Handler 提供高效的 M3U8 清洗与代理 HTTP 服务
type Handler struct {
	opts       CleanOptions
	httpClient *http.Client
	cache      sync.Map // key: targetURL, val: *cacheEntry
	cacheTTL   time.Duration
}

// NewHandler 创建 M3U8 代理与清洗处理器
func NewHandler(opts CleanOptions) *Handler {
	// 创建支持跳过无效 TLS 证书、支持超时保护的 HTTP Client
	tr := &http.Transport{
		TLSClientConfig:     &tls.Config{InsecureSkipVerify: true},
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 20,
		IdleConnTimeout:     90 * time.Second,
	}

	h := &Handler{
		opts: opts,
		httpClient: &http.Client{
			Transport: tr,
			Timeout:   10 * time.Second,
		},
		cacheTTL: 5 * time.Minute, // 默认缓存 5 分钟
	}

	// 定期清理过期缓存
	go h.cleanupCacheLoop()

	return h
}

// ServeHTTP 实现 http.Handler
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// 支持跨域访问 (CORS)
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "*")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	targetURL := strings.TrimSpace(r.URL.Query().Get("url"))
	// 容错：若未传经过严格 encodeURIComponent 的含 & 参数的链接，从 RawQuery 中提取
	if targetURL == "" {
		if idx := strings.Index(r.URL.RawQuery, "url="); idx != -1 {
			raw := r.URL.RawQuery[idx+4:]
			if unescaped, err := url.QueryUnescape(raw); err == nil && (strings.HasPrefix(unescaped, "http://") || strings.HasPrefix(unescaped, "https://")) {
				targetURL = unescaped
			} else {
				targetURL = raw
			}
		}
	}

	if targetURL == "" {
		http.Error(w, "Missing 'url' query parameter", http.StatusBadRequest)
		return
	}

	// 验证 URL 合法性
	parsedURL, err := url.Parse(targetURL)
	if err != nil {
		http.Error(w, fmt.Sprintf("Invalid target URL: %v", err), http.StatusBadRequest)
		return
	}

	scheme := strings.ToLower(parsedURL.Scheme)
	if scheme != "http" && scheme != "https" {
		http.Error(w, fmt.Sprintf("Invalid target URL scheme '%s', only http/https supported", parsedURL.Scheme), http.StatusBadRequest)
		return
	}

	// 1. 尝试从本地内存缓存读取
	if val, ok := h.cache.Load(targetURL); ok {
		entry := val.(*cacheEntry)
		if time.Now().Before(entry.expiredAt) {
			w.Header().Set("Content-Type", "application/vnd.apple.mpegurl; charset=utf-8")
			w.Header().Set("X-M3U8-AdClean-Cache", "HIT")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(entry.content))
			return
		}
		// 过期则删除
		h.cache.Delete(targetURL)
	}

	// 2. 向原始资源站发起请求
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, targetURL, nil)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create request: %v", err), http.StatusInternalServerError)
		return
	}

	// 智能伪造防盗链请求头
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "*/*")
	req.Header.Set("Referer", fmt.Sprintf("%s://%s/", parsedURL.Scheme, parsedURL.Host))

	resp, err := h.httpClient.Do(req)
	if err != nil {
		log.Printf("[M3U8-Clean] Fetch upstream failed (%s): %v", targetURL, err)
		http.Error(w, fmt.Sprintf("Fetch upstream m3u8 failed: %v", err), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		http.Error(w, fmt.Sprintf("Upstream returned HTTP %d", resp.StatusCode), resp.StatusCode)
		return
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, fmt.Sprintf("Read upstream response failed: %v", err), http.StatusInternalServerError)
		return
	}

	rawContent := string(bodyBytes)

	// 3. 执行广告清洗与绝对路径转换
	cleanedContent, err := CleanM3U8(rawContent, targetURL, h.opts)
	if err != nil {
		log.Printf("[M3U8-Clean] Clean failed (%s), fallback to raw: %v", targetURL, err)
		cleanedContent = rawContent
	}

	// 4. 存入缓存
	h.cache.Store(targetURL, &cacheEntry{
		content:   cleanedContent,
		expiredAt: time.Now().Add(h.cacheTTL),
	})

	// 5. 输出响应
	w.Header().Set("Content-Type", "application/vnd.apple.mpegurl; charset=utf-8")
	w.Header().Set("X-M3U8-AdClean-Cache", "MISS")
	w.Header().Set("X-M3U8-AdClean-Engine", "Go-AuroraClean/1.0")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(cleanedContent))
}

func (h *Handler) cleanupCacheLoop() {
	ticker := time.NewTicker(3 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		now := time.Now()
		h.cache.Range(func(key, value any) bool {
			entry, ok := value.(*cacheEntry)
			if ok && now.After(entry.expiredAt) {
				h.cache.Delete(key)
			}
			return true
		})
	}
}
