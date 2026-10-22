package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/store"
	"video-collection-service/pkg/webhook"
)

type webhookFixture struct {
	t   *testing.T
	s   *store.SQLiteStore
	mux *http.ServeMux
}

func newWebhookFixture(t *testing.T) *webhookFixture {
	t.Helper()
	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "webhook.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })
	f := &webhookFixture{t: t, s: s, mux: http.NewServeMux()}
	NewServer(s, nil, nil, nil, nil).RegisterRoutes(f.mux)
	return f
}

func (f *webhookFixture) adminToken() string {
	f.t.Helper()
	u, err := f.s.GetUserByUsername(context.Background(), "admin")
	if err != nil || u == nil {
		f.t.Fatalf("default admin missing: %v", err)
	}
	return auth.DefaultSessionManager.CreateSession(u)
}

func (f *webhookFixture) doAdmin(method, path string, body any, token string) *httptest.ResponseRecorder {
	f.t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buf)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	f.mux.ServeHTTP(rec, req)
	return rec
}

func (f *webhookFixture) doIngest(id string, rawBody []byte, headers map[string]string) *httptest.ResponseRecorder {
	f.t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/api/webhooks/"+id+"/ingest", bytes.NewReader(rawBody))
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	f.mux.ServeHTTP(rec, req)
	return rec
}

// createWebhook 通过管理接口创建端点，返回 secret 明文（仅创建时可得）。
func (f *webhookFixture) createWebhook(token string, extra map[string]any) (string, string) {
	f.t.Helper()
	payload := map[string]any{"name": "测试回调"}
	for k, v := range extra {
		payload[k] = v
	}
	rec := f.doAdmin(http.MethodPost, "/api/admin/webhooks", payload, token)
	if rec.Code != http.StatusOK {
		f.t.Fatalf("create webhook: %d %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Data struct {
			Webhook store.Webhook `json:"webhook"`
			Secret  string        `json:"secret"`
		} `json:"data"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		f.t.Fatal(err)
	}
	if resp.Data.Secret == "" {
		f.t.Fatal("secret must be returned once on create")
	}
	return resp.Data.Webhook.ID, resp.Data.Secret
}

func signedHeaders(secret string, rawBody []byte) map[string]string {
	return map[string]string{
		"X-Webhook-Signature": "sha256=" + webhook.ComputeSignature(secret, rawBody),
	}
}

func vodBody(name, url string) []byte {
	return []byte(fmt.Sprintf(`{"event":"video.upsert","data":{"list":[{"vod_id":%d,"vod_name":%q,"vod_play_from":"m3u8","vod_play_url":%q,"vod_pic":"p.jpg","vod_year":"2026"}]}}`,
		time.Now().UnixNano(), name, url))
}

// 公开入口：正确签名 → 入库 → 留痕（含原始 body）
func TestWebhookIngestAccepted(t *testing.T) {
	f := newWebhookFixture(t)
	token := f.adminToken()
	id, secret := f.createWebhook(token, nil)

	raw := vodBody("回调影片甲", "https://cdn.example.com/a/1.m3u8")
	rec := f.doIngest(id, raw, signedHeaders(secret, raw))
	if rec.Code != http.StatusOK {
		t.Fatalf("ingest = %d %s", rec.Code, rec.Body.String())
	}

	// 入库到视频库
	videos, total, err := f.s.QueryVideos(context.Background(), store.VideoQuery{Keyword: "回调影片甲"})
	if err != nil || total == 0 || len(videos) == 0 {
		t.Fatalf("video not imported: total=%d err=%v", total, err)
	}
	if videos[0].SourceID != "webhook:"+id {
		t.Errorf("source_id = %q", videos[0].SourceID)
	}
	if len(videos[0].PlayGroups) == 0 || videos[0].PlayGroups[0].SourceID != "webhook:"+id {
		t.Errorf("play groups not attached: %+v", videos[0].PlayGroups)
	}

	// 投递留痕且保存了原始报文
	dels, dtotal, err := f.s.ListWebhookDeliveries(context.Background(), store.WebhookDeliveryQuery{WebhookID: id, PageSize: 10})
	if err != nil || dtotal != 1 || len(dels) != 1 {
		t.Fatalf("deliveries = %d/%d %v", dtotal, len(dels), err)
	}
	if dels[0].Status != "accepted" || dels[0].Imported != 1 {
		t.Errorf("delivery = %+v", dels[0])
	}
	if !bytes.Contains([]byte(dels[0].RawBody), []byte("回调影片甲")) {
		t.Errorf("raw body not preserved: %q", dels[0].RawBody)
	}

	// 统计
	st, err := f.s.GetWebhookStats(context.Background(), id)
	if err != nil || st.Accepted != 1 || st.Total != 1 {
		t.Fatalf("stats = %+v %v", st, err)
	}
}

// 验签失败：错误签名 / 篡改 body / 空签名头，均 401 且不留脏数据
func TestWebhookIngestRejectsBadSignature(t *testing.T) {
	f := newWebhookFixture(t)
	token := f.adminToken()
	id, secret := f.createWebhook(token, nil)
	raw := vodBody("签名失败影片", "https://cdn.example.com/b/1.m3u8")

	for name, hdrs := range map[string]map[string]string{
		"wrong secret":  signedHeaders("totally-wrong-secret", raw),
		"tampered body": signedHeaders(secret, vodBody("被篡改", "https://x/1.m3u8")),
		"missing":       {},
	} {
		t.Run(name, func(t *testing.T) {
			rec := f.doIngest(id, raw, hdrs)
			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("status = %d %s", rec.Code, rec.Body.String())
			}
		})
	}

	_, total, _ := f.s.QueryVideos(context.Background(), store.VideoQuery{Keyword: "签名失败"})
	if total != 0 {
		t.Errorf("no video should be imported, total=%d", total)
	}
	dels, dtotal, _ := f.s.ListWebhookDeliveries(context.Background(), store.WebhookDeliveryQuery{WebhookID: id, PageSize: 10})
	if dtotal != 3 {
		t.Errorf("rejections must be traced, got %d", dtotal)
	}
	for _, d := range dels {
		if d.Status != "rejected" {
			t.Errorf("status = %q", d.Status)
		}
		if !bytes.Contains([]byte(d.RawBody), []byte("签名失败影片")) {
			t.Errorf("raw body must be traced for rejected too")
		}
	}
}

// 未知 webhook：404，不泄露存在性
func TestWebhookIngestUnknownID(t *testing.T) {
	f := newWebhookFixture(t)
	raw := vodBody("无主影片", "https://cdn.example.com/c/1.m3u8")
	rec := f.doIngest("wh_missing", raw, signedHeaders("whatever", raw))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d %s", rec.Code, rec.Body.String())
	}
}

// 时间戳防重放：过期时间戳必须拒绝
func TestWebhookIngestTimestamp(t *testing.T) {
	f := newWebhookFixture(t)
	token := f.adminToken()
	id, secret := f.createWebhook(token, map[string]any{"tolerance_sec": 300})
	raw := vodBody("重放影片", "https://cdn.example.com/d/1.m3u8")

	stale := signedHeaders(secret, raw)
	stale["X-Webhook-Timestamp"] = strconv.FormatInt(time.Now().Add(-2*time.Hour).Unix(), 10)
	if rec := f.doIngest(id, raw, stale); rec.Code != http.StatusUnauthorized {
		t.Fatalf("stale timestamp status = %d %s", rec.Code, rec.Body.String())
	}

	fresh := signedHeaders(secret, raw)
	fresh["X-Webhook-Timestamp"] = strconv.FormatInt(time.Now().Unix(), 10)
	if rec := f.doIngest(id, raw, fresh); rec.Code != http.StatusOK {
		t.Fatalf("fresh timestamp status = %d %s", rec.Code, rec.Body.String())
	}
}

// 事件白名单：不匹配的事件被忽略，不进库
func TestWebhookIngestEventWhitelist(t *testing.T) {
	f := newWebhookFixture(t)
	token := f.adminToken()
	id, secret := f.createWebhook(token, map[string]any{"events": []string{"video.approved"}})
	raw := vodBody("白名单外影片", "https://cdn.example.com/e/1.m3u8")
	rec := f.doIngest(id, raw, signedHeaders(secret, raw))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d %s", rec.Code, rec.Body.String())
	}
	_, total, _ := f.s.QueryVideos(context.Background(), store.VideoQuery{Keyword: "白名单外"})
	if total != 0 {
		t.Errorf("ignored event must not import, total=%d", total)
	}
	dels, _, _ := f.s.ListWebhookDeliveries(context.Background(), store.WebhookDeliveryQuery{WebhookID: id, PageSize: 10})
	if len(dels) != 1 || dels[0].Status != "ignored" {
		t.Fatalf("deliveries = %+v", dels)
	}
}

// duplicate=skip：第二次推送同名影片不新增
func TestWebhookIngestSkipDuplicate(t *testing.T) {
	f := newWebhookFixture(t)
	token := f.adminToken()
	id, secret := f.createWebhook(token, map[string]any{"duplicate": "skip"})
	raw := vodBody("去重影片", "https://cdn.example.com/f/1.m3u8")

	if rec := f.doIngest(id, raw, signedHeaders(secret, raw)); rec.Code != http.StatusOK {
		t.Fatalf("first = %d %s", rec.Code, rec.Body.String())
	}
	// 相同名字，不同 URL
	raw2 := vodBody("去重影片", "https://cdn.example.com/f/2.m3u8")
	if rec := f.doIngest(id, raw2, signedHeaders(secret, raw2)); rec.Code != http.StatusOK {
		t.Fatalf("second = %d %s", rec.Code, rec.Body.String())
	}
	_, total, _ := f.s.QueryVideos(context.Background(), store.VideoQuery{Keyword: "去重影片"})
	if total != 1 {
		t.Errorf("skip duplicate must keep 1 video, got %d", total)
	}
	dels, _, _ := f.s.ListWebhookDeliveries(context.Background(), store.WebhookDeliveryQuery{WebhookID: id, PageSize: 10})
	if len(dels) != 2 {
		t.Fatalf("deliveries = %d", len(dels))
	}
	var skipped int
	for _, d := range dels {
		if d.Status == "accepted" && d.Imported == 1 {
			skipped++
		}
	}
	if skipped != 1 {
		t.Errorf("exactly one delivery should import, got %d", skipped)
	}
}

// secret 从不通过读接口外泄；rotate 后旧 secret 失效、新 secret 生效
func TestWebhookSecretNeverExposedAndRotation(t *testing.T) {
	f := newWebhookFixture(t)
	token := f.adminToken()
	id, oldSecret := f.createWebhook(token, nil)

	// 列表接口不得包含明文密钥
	rec := f.doAdmin(http.MethodGet, "/api/admin/webhooks", nil, token)
	if bytes.Contains(rec.Body.Bytes(), []byte(oldSecret)) {
		t.Fatal("secret leaked in list response")
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("secret_hint")) {
		t.Error("list must expose masked hint")
	}

	raw := vodBody("轮换前影片", "https://cdn.example.com/g/1.m3u8")
	if rec := f.doIngest(id, raw, signedHeaders(oldSecret, raw)); rec.Code != http.StatusOK {
		t.Fatalf("old secret ingest = %d", rec.Code)
	}

	// 轮换
	rec = f.doAdmin(http.MethodPost, "/api/admin/webhooks/secret?id="+id, nil, token)
	if rec.Code != http.StatusOK {
		t.Fatalf("rotate = %d %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Data struct {
			Secret string `json:"secret"`
		} `json:"data"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Data.Secret == "" || resp.Data.Secret == oldSecret {
		t.Fatal("rotate must return a new secret")
	}

	// 旧密钥立即失效
	if rec := f.doIngest(id, raw, signedHeaders(oldSecret, raw)); rec.Code != http.StatusUnauthorized {
		t.Errorf("old secret after rotate = %d", rec.Code)
	}
	// 新密钥生效
	if rec := f.doIngest(id, raw, signedHeaders(resp.Data.Secret, raw)); rec.Code != http.StatusOK {
		t.Errorf("new secret after rotate = %d", rec.Code)
	}
}

// 投递日志检索与清理
func TestWebhookDeliveryPagingAndCleanup(t *testing.T) {
	f := newWebhookFixture(t)
	token := f.adminToken()
	id, secret := f.createWebhook(token, nil)
	for i := 0; i < 3; i++ {
		raw := vodBody(fmt.Sprintf("日志影片%d", i), "https://cdn.example.com/h/1.m3u8")
		f.doIngest(id, raw, signedHeaders(secret, raw))
	}
	f.doIngest(id, []byte(`{}`), signedHeaders(secret, []byte(`{}`)))

	rec := f.doAdmin(http.MethodGet, "/api/admin/webhooks/deliveries?id="+id+"&page=1&page_size=2", nil, token)
	if rec.Code != http.StatusOK {
		t.Fatalf("deliveries = %d", rec.Code)
	}
	var page struct {
		Total int                     `json:"total"`
		Data  []store.WebhookDelivery `json:"data"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &page)
	if page.Total != 4 || len(page.Data) != 2 {
		t.Fatalf("total=%d len=%d", page.Total, len(page.Data))
	}

	// 按状态过滤
	rec = f.doAdmin(http.MethodGet, "/api/admin/webhooks/deliveries?id="+id+"&status=accepted", nil, token)
	_ = json.Unmarshal(rec.Body.Bytes(), &page)
	if page.Total != 3 {
		t.Errorf("accepted = %d, want 3", page.Total)
	}

	// 统计接口
	rec = f.doAdmin(http.MethodGet, "/api/admin/webhooks/stats?id="+id, nil, token)
	if rec.Code != http.StatusOK || !bytes.Contains(rec.Body.Bytes(), []byte(`"accepted":3`)) {
		t.Errorf("stats = %d %s", rec.Code, rec.Body.String())
	}

	// 清理：days=0 表示清理全部
	rec = f.doAdmin(http.MethodPost, "/api/admin/webhooks/deliveries/cleanup", map[string]any{"id": id, "days": 0}, token)
	if rec.Code != http.StatusOK {
		t.Fatalf("cleanup = %d", rec.Code)
	}
	_, total, _ := f.s.ListWebhookDeliveries(context.Background(), store.WebhookDeliveryQuery{WebhookID: id})
	if total != 0 {
		t.Errorf("cleanup failed, total=%d", total)
	}
}

// target=record：落入通用采集记录而非视频库
func TestWebhookIngestRecordTarget(t *testing.T) {
	f := newWebhookFixture(t)
	token := f.adminToken()
	id, secret := f.createWebhook(token, map[string]any{"target": "record"})
	raw := vodBody("记录影片", "https://cdn.example.com/i/1.m3u8")
	if rec := f.doIngest(id, raw, signedHeaders(secret, raw)); rec.Code != http.StatusOK {
		t.Fatalf("ingest = %d %s", rec.Code, rec.Body.String())
	}
	recs, total, err := f.s.ListCollectionRecords(context.Background(), "webhook:"+id, 1, 10)
	if err != nil || total != 1 {
		t.Fatalf("collection records = %d %v", total, err)
	}
	if recs[0].Values["title"] != "记录影片" {
		t.Errorf("record = %+v", recs[0])
	}
	_, vtotal, _ := f.s.QueryVideos(context.Background(), store.VideoQuery{Keyword: "记录影片"})
	if vtotal != 0 {
		t.Errorf("record target must not touch video library, total=%d", vtotal)
	}
}

// 管理接口鉴权：未登录一律 401
func TestWebhookAdminRequiresAuth(t *testing.T) {
	f := newWebhookFixture(t)
	for _, tc := range []struct{ method, path string }{
		{http.MethodGet, "/api/admin/webhooks"},
		{http.MethodPost, "/api/admin/webhooks"},
		{http.MethodGet, "/api/admin/webhooks/deliveries"},
		{http.MethodPost, "/api/admin/webhooks/secret?id=wh_x"},
		{http.MethodGet, "/api/admin/webhooks/stats?id=wh_x"},
	} {
		req := httptest.NewRequest(tc.method, tc.path, nil)
		rec := httptest.NewRecorder()
		f.mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s unauthenticated = %d", tc.method, tc.path, rec.Code)
		}
	}
}

// 停用端点后拒绝投递
func TestWebhookDisabledRejects(t *testing.T) {
	f := newWebhookFixture(t)
	token := f.adminToken()
	id, secret := f.createWebhook(token, nil)
	_ = f.s.UpdateWebhook(context.Background(), &store.Webhook{ID: id, Name: "x", Target: "video", Duplicate: "update", Enabled: false})
	raw := vodBody("停用影片", "https://cdn.example.com/j/1.m3u8")
	if rec := f.doIngest(id, raw, signedHeaders(secret, raw)); rec.Code != http.StatusNotFound {
		t.Errorf("disabled webhook = %d", rec.Code)
	}
}
