package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/integration"
	"video-collection-service/pkg/notify"
	"video-collection-service/pkg/storage"
)

// mailer 按当前配置构建通知服务：配置改完即时生效，不需要重启进程。
func (srv *Server) mailer(ctx context.Context) *notify.Service {
	return notify.FromConfig(integration.Load(ctx, srv.store), notify.DevCodeEnabled())
}

// uploader 按当前配置构建存储实现（local / oss / s3）。
func (srv *Server) uploader(ctx context.Context) (storage.Uploader, error) {
	return storage.New(integration.Load(ctx, srv.store).Storage, UploadDir())
}

// handleAdminIntegrations 读取 / 保存外部服务接入配置。
// 读取对全体后台角色开放（密钥已脱敏），保存仅限超级管理员。
func (srv *Server) handleAdminIntegrations(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		cfg := integration.Load(r.Context(), srv.store)
		jsonResponse(w, http.StatusOK, map[string]any{
			"code":     1,
			"data":     cfg.Masked(),
			"dev_mode": notify.DevCodeEnabled(),
		})

	case http.MethodPost:
		u := auth.GetCurrentUser(r, srv.store)
		if u == nil || u.Role != "super_admin" {
			errorResponse(w, http.StatusForbidden, "仅超级管理员可修改集成配置")
			return
		}
		// 这里刻意不使用 contentBody 的 DisallowUnknownFields：
		// 前端会把带 pass_set / configured 的只读字段一并回传，宽容解析更稳妥。
		raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<20))
		if err != nil {
			errorResponse(w, http.StatusBadRequest, "读取参数失败")
			return
		}
		var req integration.Config
		if err := json.Unmarshal(raw, &req); err != nil {
			errorResponse(w, http.StatusBadRequest, "参数解析失败: "+err.Error())
			return
		}
		if err := integration.Save(r.Context(), srv.store, req); err != nil {
			errorResponse(w, http.StatusInternalServerError, "保存失败: "+err.Error())
			return
		}
		name := strings.TrimSpace(u.Nickname)
		if name == "" {
			name = u.Username
		}
		srv.logSystemActor(r, u.ID, name, "info", "system", "更新集成配置", map[string]any{
			"mail_enabled":     req.Mail.Enabled,
			"sms_enabled":      req.SMS.Enabled,
			"storage_provider": req.Storage.Provider,
		})
		cfg := integration.Load(r.Context(), srv.store)
		jsonResponse(w, http.StatusOK, map[string]any{
			"code": 1,
			"msg":  "集成配置已保存",
			"data": cfg.Masked(),
		})

	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// handleTestMail 用已保存的配置给自己发一封测试邮件。
func (srv *Server) handleTestMail(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	var req struct {
		To string `json:"to"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	to := strings.TrimSpace(req.To)
	if to == "" || !emailPattern.MatchString(to) {
		errorResponse(w, http.StatusBadRequest, "请填写正确的收件邮箱")
		return
	}
	mailer := srv.mailer(r.Context())
	if err := mailer.SendMail(to, "【测试】邮件通道连通性检查", fmt.Sprintf(
		"这是一封来自后台「集成配置」的测试邮件。\r\n\r\n发送时间：%s\r\n如您收到本邮件，说明 SMTP 配置已生效。",
		time.Now().Format("2006-01-02 15:04:05"))); err != nil {
		errorResponse(w, http.StatusBadGateway, "发送失败: "+err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "测试邮件已发送至 " + to})
}

// handleTestSMS 用已保存的配置发一条测试短信。
func (srv *Server) handleTestSMS(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	var req struct {
		Phone string `json:"phone"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	phone := strings.TrimSpace(req.Phone)
	if _, msg := normalizeContact(notify.ChannelPhone, phone); msg != "" {
		errorResponse(w, http.StatusBadRequest, msg)
		return
	}
	mailer := srv.mailer(r.Context())
	if err := mailer.SendSMS(r.Context(), phone, "【测试】短信通道连通性检查，收到即表示配置已生效。"); err != nil {
		errorResponse(w, http.StatusBadGateway, "发送失败: "+err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "测试短信已发送至 " + phone})
}

// handleTestStorage 上传一个探针文件再删除，验证写入与删除权限。
func (srv *Server) handleTestStorage(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	up, err := srv.uploader(r.Context())
	if err != nil {
		errorResponse(w, http.StatusBadRequest, "存储配置不可用: "+err.Error())
		return
	}
	key := fmt.Sprintf("probe/%d.txt", time.Now().UnixNano())
	content := []byte("video-collection storage probe " + time.Now().Format(time.RFC3339))
	url, err := up.Put(r.Context(), key, content, "text/plain; charset=utf-8")
	if err != nil {
		errorResponse(w, http.StatusBadGateway, "上传失败: "+err.Error())
		return
	}
	if err := up.Delete(r.Context(), key); err != nil {
		jsonResponse(w, http.StatusOK, map[string]any{
			"code": 1,
			"msg":  "上传成功，但删除失败（请检查删除权限）: " + err.Error(),
			"data": map[string]any{"provider": up.Kind(), "url": url, "deleted": false},
		})
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  "存储读写正常",
		"data": map[string]any{"provider": up.Kind(), "url": url, "deleted": true},
	})
}
