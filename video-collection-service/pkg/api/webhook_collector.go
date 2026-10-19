package api

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
	"unicode/utf8"

	"video-collection-service/config"
	"video-collection-service/pkg/store"
)

const (
	defaultWebhookCollectorID = "acg-news"
	maxCollectorWebhookBody   = 8 << 20 // 8 MiB
)

// collectorWebhookItem 兼容 acg-news push_webhook 字段，也接受其他采集器同类 JSON。
type collectorWebhookItem struct {
	ID             json.RawMessage         `json:"id"`
	Category       string                  `json:"category"`
	Source         string                  `json:"source"`
	SourceName     string                  `json:"source_name"`
	SourceLabel    string                  `json:"source_label"`
	Kind           string                  `json:"kind"`
	Lang           string                  `json:"lang"`
	TitleOriginal  string                  `json:"title_original"`
	TitleZh        *string                 `json:"title_zh"`
	SummaryZh      *string                 `json:"summary_zh"`
	TextZh         *string                 `json:"text_zh"`
	URL            string                  `json:"url"`
	PublishedAt    string                  `json:"published_at"`
	AlsoReportedBy json.RawMessage         `json:"also_reported_by"`
	Images         []collectorWebhookImage `json:"images"`
}

type collectorWebhookImage struct {
	URL       string  `json:"url"`
	LocalPath *string `json:"local_path"`
}

func collectorWebhookSecret() string {
	if s := strings.TrimSpace(os.Getenv("COLLECTOR_WEBHOOK_SECRET")); s != "" {
		return s
	}
	return strings.TrimSpace(os.Getenv("ACG_WEBHOOK_SECRET"))
}

func verifyCollectorSignature(secret string, body []byte, header string) bool {
	header = strings.TrimSpace(header)
	if header == "" || secret == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write(body)
	expected := "sha256=" + hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(header))
}

func resolveCollectorSourceID(r *http.Request) string {
	if id := strings.TrimSpace(r.URL.Query().Get("collector")); id != "" {
		return id
	}
	if id := strings.TrimSpace(r.Header.Get("X-ACG-Collector-Id")); id != "" {
		return id
	}
	if id := strings.TrimSpace(r.Header.Get("X-Collector-Id")); id != "" {
		return id
	}
	return defaultWebhookCollectorID
}

// resolveWebhookAuth 按采集源 custom_params 优先、环境变量兜底解析验签密钥。
// 规则：webhook 源存在且 enabled=false → 403；密钥过期 → 401；无密钥 → 503。
func (srv *Server) resolveWebhookAuth(r *http.Request, sourceID string) (secret string, code int, msg string) {
	src, err := srv.store.GetSourceByID(r.Context(), sourceID)
	if err != nil {
		return "", http.StatusInternalServerError, "读取采集源失败"
	}
	if src != nil && config.IsWebhookSource(*src) {
		if !src.Enabled {
			return "", http.StatusForbidden, "采集源已关闭"
		}
		params := src.CustomParams
		if params == nil {
			params = src.Filter.CustomParams
		}
		if params != nil {
			if s := strings.TrimSpace(params["webhook_secret"]); s != "" {
				if expRaw := strings.TrimSpace(params["webhook_secret_expires_at"]); expRaw != "" {
					exp, perr := config.ParseWebhookSecretExpiry(expRaw)
					if perr != nil {
						return "", http.StatusUnauthorized, "密钥过期时间配置无效"
					}
					if time.Now().After(exp) {
						return "", http.StatusUnauthorized, "Webhook 密钥已过期"
					}
				}
				return s, 0, ""
			}
		}
	}

	// 环境变量兜底（源未配置 webhook_secret 时；源若已关闭则上一段已 403）
	if s := collectorWebhookSecret(); s != "" {
		return s, 0, ""
	}
	return "", http.StatusServiceUnavailable, "未配置 Webhook 密钥：请在使魔节点管理中设置 webhook_secret，或设置环境变量 COLLECTOR_WEBHOOK_SECRET / ACG_WEBHOOK_SECRET"
}

func derefStr(p *string) string {
	if p == nil {
		return ""
	}
	return strings.TrimSpace(*p)
}

func firstRemoteImageURL(images []collectorWebhookImage) string {
	for _, img := range images {
		u := strings.TrimSpace(img.URL)
		if strings.HasPrefix(u, "http://") || strings.HasPrefix(u, "https://") {
			return u
		}
	}
	return ""
}

func remoteImageURLsJSON(images []collectorWebhookImage) string {
	urls := make([]string, 0, len(images))
	for _, img := range images {
		u := strings.TrimSpace(img.URL)
		if strings.HasPrefix(u, "http://") || strings.HasPrefix(u, "https://") {
			urls = append(urls, u)
		}
	}
	b, _ := json.Marshal(urls)
	return string(b)
}

func externalIDFromRaw(raw json.RawMessage) string {
	s := strings.TrimSpace(string(raw))
	if s == "" || s == "null" {
		return ""
	}
	var asString string
	if err := json.Unmarshal(raw, &asString); err == nil {
		return strings.TrimSpace(asString)
	}
	var asNum json.Number
	if err := json.Unmarshal(raw, &asNum); err == nil {
		return asNum.String()
	}
	return strings.Trim(s, `"`)
}

func truncateRunes(s string, max int) string {
	if utf8.RuneCountInString(s) <= max {
		return s
	}
	return string([]rune(s)[:max])
}


// synthesizeCollectorContent 在 summary/text 皆空时拼可读正文，避免只落到原标题。
func synthesizeCollectorContent(it collectorWebhookItem, title string) string {
	if s := derefStr(it.SummaryZh); s != "" {
		return s
	}
	if s := derefStr(it.TextZh); s != "" {
		return s
	}
	sourceLabel := strings.TrimSpace(it.SourceLabel)
	if sourceLabel == "" {
		sourceLabel = strings.TrimSpace(it.SourceName)
	}
	if sourceLabel == "" {
		sourceLabel = strings.TrimSpace(it.Source)
	}
	var lines []string
	if sourceLabel != "" {
		lines = append(lines, "来源："+sourceLabel)
	}
	if u := strings.TrimSpace(it.URL); u != "" {
		lines = append(lines, "原文："+u)
	}
	orig := strings.TrimSpace(it.TitleOriginal)
	if orig == "" {
		orig = title
	}
	if orig != "" {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, orig)
	}
	if len(lines) == 0 {
		return title
	}
	return strings.Join(lines, "\n")
}

func mapCollectorItemToArticle(it collectorWebhookItem) (key string, values map[string]string, err error) {
	extID := externalIDFromRaw(it.ID)
	if extID == "" {
		return "", nil, fmt.Errorf("缺少 id")
	}
	src := strings.TrimSpace(it.Source)
	if src != "" {
		key = src + ":" + extID
	} else {
		key = extID
	}

	title := derefStr(it.TitleZh)
	if title == "" {
		title = strings.TrimSpace(it.TitleOriginal)
	}
	if title == "" {
		return "", nil, fmt.Errorf("条目 %s 缺少标题", key)
	}
	title = truncateRunes(title, 200)

	summary := derefStr(it.SummaryZh)
	content := synthesizeCollectorContent(it, title)
	content = truncateRunes(content, 50000)
	summary = truncateRunes(summary, 1000)
	category := truncateRunes(strings.TrimSpace(it.Category), 50)

	also := "[]"
	if len(it.AlsoReportedBy) > 0 && string(it.AlsoReportedBy) != "null" {
		also = string(it.AlsoReportedBy)
	}

	values = map[string]string{
		"title":            title,
		"content":          content,
		"summary":          summary,
		"cover":            firstRemoteImageURL(it.Images),
		"category":         category,
		"status":           "draft",
		"url":              strings.TrimSpace(it.URL),
		"source":           src,
		"source_name":      strings.TrimSpace(it.SourceName),
		"source_label":     strings.TrimSpace(it.SourceLabel),
		"kind":             strings.TrimSpace(it.Kind),
		"lang":             strings.TrimSpace(it.Lang),
		"title_original":   strings.TrimSpace(it.TitleOriginal),
		"published_at":     strings.TrimSpace(it.PublishedAt),
		"external_id":      extID,
		"also_reported_by": also,
		"images":           remoteImageURLsJSON(it.Images),
	}
	return key, values, nil
}

func (srv *Server) ensureWebhookSource(r *http.Request, sourceID string) {
	ctx := r.Context()
	if existing, err := srv.store.GetSourceByID(ctx, sourceID); err == nil && existing != nil {
		return
	}
	name := sourceID
	if sourceID == defaultWebhookCollectorID {
		name = "ACG 资讯 Webhook"
	}
	_ = srv.store.SaveSource(ctx, config.SourceConfig{
		ID:         sourceID,
		Name:       name,
		API:        "webhook://collector",
		Type:       "webhook",
		Enabled:    false,
		TimeoutSec: 15,
		PageLimit:  1,
	})
}

// handleCollectorWebhook 通用采集 Webhook：验签后写入既有 article→news 采集链路。
// POST /api/webhooks/collector
func (srv *Server) handleCollectorWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	sourceID := resolveCollectorSourceID(r)
	secret, code, msg := srv.resolveWebhookAuth(r, sourceID)
	if code != 0 {
		errorResponse(w, code, msg)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxCollectorWebhookBody)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			errorResponse(w, http.StatusRequestEntityTooLarge, "请求体过大")
			return
		}
		errorResponse(w, http.StatusBadRequest, "读取请求体失败")
		return
	}

	sig := r.Header.Get("X-ACG-Signature")
	if sig == "" {
		sig = r.Header.Get("X-Collector-Signature")
	}
	if !verifyCollectorSignature(secret, body, sig) {
		errorResponse(w, http.StatusUnauthorized, "签名无效")
		return
	}

	var items []collectorWebhookItem
	if err := json.Unmarshal(body, &items); err != nil {
		errorResponse(w, http.StatusBadRequest, "JSON 必须是对象数组")
		return
	}
	if len(items) == 0 {
		jsonResponse(w, http.StatusOK, map[string]any{"ok": true, "received": 0, "inserted": 0, "updated": 0})
		return
	}
	if len(items) > 200 {
		errorResponse(w, http.StatusBadRequest, "单批最多 200 条")
		return
	}

	srv.ensureWebhookSource(r, sourceID)
	batchID := strings.TrimSpace(r.Header.Get("X-ACG-Batch-Id"))
	if batchID == "" {
		batchID = strings.TrimSpace(r.Header.Get("X-Collector-Batch-Id"))
	}

	inserted, updated := 0, 0
	for i, it := range items {
		key, values, mapErr := mapCollectorItemToArticle(it)
		if mapErr != nil {
			errorResponse(w, http.StatusBadRequest, fmt.Sprintf("第 %d 条: %v", i+1, mapErr))
			return
		}
		if batchID != "" {
			values["batch_id"] = batchID
		}
		existed, err := srv.store.HasCollectionRecord(r.Context(), sourceID, "article", key)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, "查询采集记录失败")
			return
		}
		rec := store.CollectionRecord{
			SourceID: sourceID,
			Target:   "article",
			Key:      key,
			Values:   values,
		}
		saved, err := srv.store.SaveCollectionRecord(r.Context(), rec, false)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, "写入资讯失败: "+err.Error())
			return
		}
		if !saved {
			continue
		}
		if existed {
			updated++
		} else {
			inserted++
		}
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"ok":        true,
		"received":  len(items),
		"inserted":  inserted,
		"updated":   updated,
		"source_id": sourceID,
	})
}
