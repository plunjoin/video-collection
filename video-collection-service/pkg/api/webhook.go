package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/store"
	"video-collection-service/pkg/webhook"
)

// webhookBodyLimit 单次投递请求体上限（原始报文全量留痕）。
const webhookBodyLimit = 4 * 1024 * 1024

// registerWebhookRoutes 注册 webhook 管理接口（管理员鉴权）与公开采集入口（签名鉴权）。
func (srv *Server) registerWebhookRoutes(mux *http.ServeMux) {
	// 公开采集入口：POST /api/webhooks/{id}/ingest，凭 HMAC 签名 + 时间戳准入
	mux.HandleFunc("POST /api/webhooks/{id}/ingest", srv.handleWebhookIngest)

	admin := func(h http.HandlerFunc) http.HandlerFunc { return auth.AdminRequired(srv.store, h) }
	mux.HandleFunc("/api/admin/webhooks", admin(srv.handleAdminWebhooks))
	mux.HandleFunc("/api/admin/webhooks/secret", admin(srv.handleAdminWebhookSecret))
	mux.HandleFunc("/api/admin/webhooks/deliveries", admin(srv.handleAdminWebhookDeliveries))
	mux.HandleFunc("/api/admin/webhooks/stats", admin(srv.handleAdminWebhookStats))
	mux.HandleFunc("/api/admin/webhooks/deliveries/cleanup", admin(srv.handleAdminWebhookCleanup))
}

// ---------- 公开采集入口 ----------

// handleWebhookIngest 处理外部系统回调：原始 body → 验签 → 防重放 → 事件白名单 → 入库 → 留痕。
func (srv *Server) handleWebhookIngest(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	rawBody, err := io.ReadAll(http.MaxBytesReader(w, r.Body, webhookBodyLimit))
	if err != nil {
		errorResponse(w, http.StatusBadRequest, "读取请求体失败（上限 4 MB）")
		return
	}
	remote := webhook.RemoteAddr(r.RemoteAddr, r.Header.Get("X-Forwarded-For"))

	wh, err := srv.store.GetWebhook(r.Context(), id)
	if err != nil {
		srv.recordDelivery(id, "", "error", 0, "查询 webhook 失败: "+err.Error(), remote, rawBody)
		errorResponse(w, http.StatusInternalServerError, "服务器内部错误")
		return
	}
	if wh == nil || !wh.Enabled {
		// 不存在或已停用：不泄露存在性，统一 404
		errorResponse(w, http.StatusNotFound, "webhook 不存在或已停用")
		return
	}

	secret, err := srv.webhookSecret(id)
	if err != nil {
		srv.recordDelivery(id, wh.Name, "error", 0, "密钥解密失败: "+err.Error(), remote, rawBody)
		errorResponse(w, http.StatusInternalServerError, "服务器内部错误")
		return
	}

	// 1) 验签（HMAC-SHA256，常量时间比对）
	sig := webhook.PickSignatureHeader(r.Header.Get, webhook.DefaultSignatureHeaders)
	if !webhook.VerifySignature(secret, sig, rawBody) {
		srv.recordDelivery(id, wh.Name, "rejected", 0, "签名校验失败", remote, rawBody)
		errorResponse(w, http.StatusUnauthorized, "签名校验失败")
		return
	}

	// 2) 防重放：携带时间戳头时必须落在容忍窗口内
	if wh.ToleranceSec > 0 {
		ts := webhook.CheckTimestamp(r.Header.Get, wh.ToleranceSec, time.Now())
		if ts.Provided && ts.Reason != "" {
			srv.recordDelivery(id, wh.Name, "rejected", 0, ts.Reason, remote, rawBody)
			errorResponse(w, http.StatusUnauthorized, ts.Reason)
			return
		}
	}

	// 3) 解析原始报文
	payload, perr := webhook.ParsePayload(rawBody)
	if perr != nil {
		srv.recordDelivery(id, wh.Name, "error", 0, perr.Error(), remote, rawBody)
		errorResponse(w, http.StatusBadRequest, perr.Error())
		return
	}

	// 4) 事件白名单
	if !webhook.AllowsEvent(wh.Events, payload.Event) {
		srv.recordDelivery(id, wh.Name, "ignored", 0, "事件类型不在白名单: "+payload.Event, remote, rawBody)
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "事件类型不在白名单，已忽略", "data": map[string]any{"ignored": true}})
		return
	}

	// 5) 入库
	sourceID := wh.SourceID
	if sourceID == "" {
		sourceID = "webhook:" + wh.ID
	}
	imported, skipped, ierr := srv.importWebhookPayload(r.Context(), wh, sourceID, payload)
	if ierr != nil {
		srv.recordDelivery(id, wh.Name, "error", imported, ierr.Error(), remote, rawBody)
		errorResponse(w, http.StatusInternalServerError, "入库失败: "+ierr.Error())
		return
	}

	srv.recordDelivery(id, wh.Name, "accepted", imported, fmt.Sprintf("入库 %d 条，跳过 %d 条", imported, skipped), remote, rawBody)
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  fmt.Sprintf("已接收 %d 条视频数据", imported),
		"data": map[string]any{"imported": imported, "skipped": skipped, "event": payload.Event},
	})
}

// webhookSecret 解密 webhook 密钥信封，返回明文密钥（仅用于内存中的验签计算）。
func (srv *Server) webhookSecret(id string) (string, error) {
	cipherText, err := srv.store.GetWebhookSecret(context.Background(), id)
	if err != nil {
		return "", err
	}
	if cipherText == "" {
		return "", fmt.Errorf("webhook 密钥缺失")
	}
	return webhook.DecryptSecret(cipherText)
}

// importWebhookPayload 按目标类型入库：video 走视频库（去重/更新），record 走通用采集记录。
func (srv *Server) importWebhookPayload(ctx context.Context, wh *store.Webhook, sourceID string, payload *webhook.Payload) (imported, skipped int, err error) {
	webhook.AttachSource(payload.Videos, sourceID, wh.Name)
	switch wh.Target {
	case "record":
		records := webhook.ToRecords(payload)
		for i, rec := range records {
			dup := false
			if wh.Duplicate == "skip" {
				dup, _ = srv.store.HasCollectionRecord(ctx, sourceID, "record", rec["title"]+"#"+strconv.Itoa(payload.Videos[i].OriginalID))
			}
			if dup {
				skipped++
				continue
			}
			if serr := srv.saveWebhookRecord(ctx, sourceID, rec, payload.Videos[i].OriginalID); serr != nil {
				return imported, skipped, serr
			}
			imported++
		}
	default: // video
		for i := range payload.Videos {
			if wh.Duplicate == "skip" {
				exists, _ := srv.store.HasVideoByName(ctx, payload.Videos[i].Name)
				if exists {
					skipped++
					continue
				}
			}
			if _, uerr := srv.store.UpsertVideo(ctx, sourceID, &payload.Videos[i]); uerr != nil {
				return imported, skipped, uerr
			}
			imported++
		}
	}
	return imported, skipped, nil
}

func (srv *Server) saveWebhookRecord(ctx context.Context, sourceID string, rec map[string]string, originalID int) error {
	key := rec["title"] + "#" + strconv.Itoa(originalID)
	_, err := srv.store.SaveCollectionRecord(ctx, store.CollectionRecord{
		SourceID: sourceID,
		Target:   "record",
		Key:      key,
		Values:   rec,
	}, false)
	return err
}

// recordDelivery 记录一次投递留痕（失败不影响主流程，仅打日志由调用方忽略）。
func (srv *Server) recordDelivery(webhookID, name, status string, imported int, errMsg, remote string, rawBody []byte) {
	_ = srv.store.RecordWebhookDelivery(context.Background(), &store.WebhookDelivery{
		WebhookID:    webhookID,
		WebhookName:  name,
		Status:       status,
		Imported:     imported,
		ErrorMessage: errMsg,
		RemoteIP:     remote,
		RawBody:      string(rawBody),
	})
}

// ---------- 管理接口 ----------

// handleAdminWebhooks 列表（GET）/ 创建（POST）。
func (srv *Server) handleAdminWebhooks(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		list, err := srv.store.ListWebhooks(r.Context())
		if err != nil {
			errorResponse(w, 500, "读取 webhook 列表失败: "+err.Error())
			return
		}
		if list == nil {
			list = []store.Webhook{}
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "data": list})

	case http.MethodPost:
		var req struct {
			Name         string   `json:"name"`
			Target       string   `json:"target"`
			Duplicate    string   `json:"duplicate"`
			Events       []string `json:"events"`
			SourceID     string   `json:"source_id"`
			ToleranceSec int      `json:"tolerance_sec"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024*1024)).Decode(&req); err != nil {
			errorResponse(w, 400, "参数解析失败")
			return
		}
		req.Name = strings.TrimSpace(req.Name)
		if req.Name == "" {
			errorResponse(w, 400, "请填写 webhook 名称")
			return
		}
		if req.Target == "" {
			req.Target = "video"
		}
		if req.Duplicate == "" {
			req.Duplicate = "update"
		}
		if req.ToleranceSec < 0 || req.ToleranceSec > 86400 {
			errorResponse(w, 400, "时间戳容忍窗口须为 0–86400 秒")
			return
		}
		// 生成明文密钥（仅此刻返回一次），加密信封落库
		plain, err := webhook.GenerateSecret()
		if err != nil {
			errorResponse(w, 500, "生成密钥失败: "+err.Error())
			return
		}
		cipherText, err := webhook.EncryptSecret(plain)
		if err != nil {
			errorResponse(w, 500, "密钥加密失败: "+err.Error())
			return
		}
		wh := &store.Webhook{
			ID:           "wh_" + strconv.FormatInt(time.Now().UnixNano(), 10),
			Name:         req.Name,
			SecretHint:   webhook.SecretHint(plain),
			Target:       req.Target,
			Duplicate:    req.Duplicate,
			Events:       req.Events,
			SourceID:     strings.TrimSpace(req.SourceID),
			ToleranceSec: req.ToleranceSec,
			Enabled:      true,
		}
		if err := srv.store.CreateWebhook(r.Context(), wh, cipherText); err != nil {
			errorResponse(w, 500, "创建失败: "+err.Error())
			return
		}
		jsonResponse(w, 200, map[string]any{
			"code": 1,
			"msg":  "创建成功，密钥仅本次返回，请妥善保存",
			"data": map[string]any{
				"webhook": wh,
				"secret":  plain,
			},
		})

	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// handleAdminWebhookSecret 轮换密钥：POST /api/admin/webhooks/secret?id=
func (srv *Server) handleAdminWebhookSecret(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		errorResponse(w, 400, "缺少 webhook id")
		return
	}
	wh, err := srv.store.GetWebhook(r.Context(), id)
	if err != nil || wh == nil {
		errorResponse(w, 404, "webhook 不存在")
		return
	}
	plain, err := webhook.GenerateSecret()
	if err != nil {
		errorResponse(w, 500, "生成密钥失败: "+err.Error())
		return
	}
	cipherText, err := webhook.EncryptSecret(plain)
	if err != nil {
		errorResponse(w, 500, "密钥加密失败: "+err.Error())
		return
	}
	if err := srv.store.RotateWebhookSecret(r.Context(), id, cipherText, webhook.SecretHint(plain)); err != nil {
		errorResponse(w, 500, "轮换失败: "+err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{
		"code": 1,
		"msg":  "密钥已轮换，旧密钥立即失效；新密钥仅本次返回",
		"data": map[string]any{"id": id, "secret": plain},
	})
}

// handleAdminWebhookDeliveries 投递日志：GET /api/admin/webhooks/deliveries
func (srv *Server) handleAdminWebhookDeliveries(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	q := r.URL.Query()
	page, _ := strconv.Atoi(q.Get("page"))
	size, _ := strconv.Atoi(q.Get("page_size"))
	list, total, err := srv.store.ListWebhookDeliveries(r.Context(), store.WebhookDeliveryQuery{
		WebhookID: strings.TrimSpace(q.Get("id")),
		Status:    strings.TrimSpace(q.Get("status")),
		Keyword:   strings.TrimSpace(q.Get("keyword")),
		Page:      page,
		PageSize:  size,
	})
	if err != nil {
		errorResponse(w, 500, "读取投递日志失败: "+err.Error())
		return
	}
	if list == nil {
		list = []store.WebhookDelivery{}
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": list, "total": total, "page": page, "page_size": size})
}

// handleAdminWebhookStats 单端点统计：GET /api/admin/webhooks/stats?id=
func (srv *Server) handleAdminWebhookStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		errorResponse(w, 400, "缺少 webhook id")
		return
	}
	st, err := srv.store.GetWebhookStats(r.Context(), id)
	if err != nil {
		errorResponse(w, 500, "统计失败: "+err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": st})
}

// handleAdminWebhookCleanup 清理投递日志：POST /api/admin/webhooks/deliveries/cleanup
func (srv *Server) handleAdminWebhookCleanup(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	var req struct {
		ID   string `json:"id"`
		Days int    `json:"days"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	// days > 0 保留天数；0 表示清理全部；缺省（<0）按 30 天
	if req.Days < 0 {
		req.Days = 30
	}
	deleted, err := srv.store.ClearWebhookDeliveries(r.Context(), strings.TrimSpace(req.ID), req.Days)
	if err != nil {
		errorResponse(w, 500, "清理失败: "+err.Error())
		return
	}
	msg := fmt.Sprintf("已清理 %d 天前的投递日志（共 %d 条）", req.Days, deleted)
	if req.Days == 0 {
		msg = fmt.Sprintf("已清理全部投递日志（共 %d 条）", deleted)
	}
	jsonResponse(w, 200, map[string]any{
		"code": 1,
		"msg":  msg,
		"data": map[string]any{"deleted": deleted},
	})
}
