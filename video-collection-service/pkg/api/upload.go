package api

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/storage"
	"video-collection-service/pkg/store"
)

const (
	// 头像单文件上限 2MB；请求体留 512KB 余量给 multipart 头。
	avatarMaxBytes  = 2 << 20
	avatarBodySlack = 512 << 10
	uploadURLPrefix = "/uploads"
)

// UploadDir 返回本地上传根目录，可用 UPLOAD_DIR 覆盖（默认 data/uploads，已在 .gitignore 内）。
func UploadDir() string {
	if dir := strings.TrimSpace(os.Getenv("UPLOAD_DIR")); dir != "" {
		return dir
	}
	return filepath.Join("data", "uploads")
}

// registerUploadRoutes 托管 /uploads/ 静态目录。
// 仅当存储类型为 local 时才有意义；OSS / S3 模式下文件由对象存储直接提供。
func (srv *Server) registerUploadRoutes(mux *http.ServeMux) {
	dir := UploadDir()
	_ = os.MkdirAll(filepath.Join(dir, "avatars"), 0o755)

	fs := http.FileServer(http.Dir(dir))
	mux.Handle(uploadURLPrefix+"/", http.StripPrefix(uploadURLPrefix+"/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 上传目录只放静态图片：禁目录列表，统一长缓存并禁止 MIME 嗅探。
		if r.URL.Path == "" || strings.HasSuffix(r.URL.Path, "/") {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Cache-Control", "public, max-age=86400")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		fs.ServeHTTP(w, r)
	})))
}

// avatarExt 只认图片魔数，扩展名由内容类型决定，不信任上传文件名。
func avatarExt(contentType string) (string, bool) {
	switch contentType {
	case "image/jpeg":
		return "jpg", true
	case "image/png":
		return "png", true
	case "image/webp":
		return "webp", true
	case "image/gif":
		return "gif", true
	}
	return "", false
}

func randomHex(n int) string {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return fmt.Sprintf("%x", time.Now().UnixNano())[:n*2]
	}
	return hex.EncodeToString(buf)
}

// handleUploadAvatar 接收 multipart 头像，写入存储后端并记入历史。
func (srv *Server) handleUploadAvatar(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, avatarMaxBytes+avatarBodySlack)
	if err := r.ParseMultipartForm(avatarMaxBytes); err != nil {
		errorResponse(w, http.StatusRequestEntityTooLarge, "图片不能超过 2MB")
		return
	}
	file, _, err := r.FormFile("file")
	if err != nil {
		errorResponse(w, http.StatusBadRequest, "请选择要上传的图片")
		return
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, avatarMaxBytes+1))
	if err != nil {
		errorResponse(w, http.StatusBadRequest, "读取图片失败")
		return
	}
	if len(data) > avatarMaxBytes {
		errorResponse(w, http.StatusRequestEntityTooLarge, "图片不能超过 2MB")
		return
	}
	contentType := http.DetectContentType(data)
	ext, ok := avatarExt(contentType)
	if !ok {
		errorResponse(w, http.StatusBadRequest, "仅支持 JPG / PNG / WebP / GIF 图片")
		return
	}

	up, err := srv.uploader(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "存储配置不可用: "+err.Error())
		return
	}
	key := fmt.Sprintf("avatars/%d-%d-%s.%s", u.ID, time.Now().UnixNano(), randomHex(4), ext)
	avatarURL, err := up.Put(r.Context(), key, data, contentType)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "头像上传失败: "+err.Error())
		return
	}

	if _, err := srv.store.AddAvatar(r.Context(), u.ID, avatarURL, key, up.Kind()); err != nil {
		log.Printf("[avatar] 写入历史失败: %v", err)
	}
	if err := srv.store.UpdateAvatar(r.Context(), u.ID, avatarURL); err != nil {
		_ = up.Delete(r.Context(), key)
		errorResponse(w, http.StatusInternalServerError, "头像保存失败，请稍后重试")
		return
	}
	srv.trimAvatarHistory(r.Context(), u.ID, avatarURL)

	actor := strings.TrimSpace(u.Nickname)
	if actor == "" {
		actor = u.Username
	}
	srv.logSystemActor(r, u.ID, actor, "info", "auth", "更新头像", map[string]any{
		"username": u.Username,
		"provider": up.Kind(),
	})

	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  "头像已更新",
		"url":  avatarURL,
		"data": map[string]any{"avatar": avatarURL, "provider": up.Kind()},
	})
}

// handleAvatars GET 列出历史头像；DELETE ?id= 删除某条历史（同时删源文件）。
func (srv *Server) handleAvatars(w http.ResponseWriter, r *http.Request) {
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}

	switch r.Method {
	case http.MethodGet:
		list, err := srv.store.ListAvatars(r.Context(), u.ID, 50)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, "读取头像历史失败")
			return
		}
		out := make([]map[string]any, 0, len(list))
		for _, item := range list {
			out = append(out, map[string]any{
				"id":         item.ID,
				"url":        item.URL,
				"provider":   item.Provider,
				"created_at": item.CreatedAt,
				"current":    item.URL == u.Avatar,
			})
		}
		jsonResponse(w, http.StatusOK, map[string]any{
			"code":    1,
			"data":    out,
			"current": u.Avatar,
		})

	case http.MethodDelete:
		id, ok := parseIntQuery(r, "id")
		if !ok {
			errorResponse(w, http.StatusBadRequest, "缺少头像 id")
			return
		}
		item, err := srv.store.GetAvatar(r.Context(), u.ID, id)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, "读取头像记录失败")
			return
		}
		if item == nil {
			errorResponse(w, http.StatusNotFound, "头像记录不存在")
			return
		}
		if item.URL == u.Avatar {
			errorResponse(w, http.StatusBadRequest, "当前正在使用的头像不能删除，请先切换到其他头像")
			return
		}
		if err := srv.store.DeleteAvatar(r.Context(), u.ID, id); err != nil {
			errorResponse(w, http.StatusInternalServerError, "删除失败，请稍后重试")
			return
		}
		// 记录删掉后同步清理源文件，避免对象存储里留孤儿文件。
		srv.deleteAvatarObject(r.Context(), *item)
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "头像已删除"})

	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// handleUseAvatar 把历史头像切换为当前头像。
func (srv *Server) handleUseAvatar(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}
	var req struct {
		ID int `json:"id"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	item, err := srv.store.GetAvatar(r.Context(), u.ID, req.ID)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "读取头像记录失败")
		return
	}
	if item == nil {
		errorResponse(w, http.StatusNotFound, "头像记录不存在")
		return
	}
	if err := srv.store.UpdateAvatar(r.Context(), u.ID, item.URL); err != nil {
		errorResponse(w, http.StatusInternalServerError, "切换失败，请稍后重试")
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  "已切换头像",
		"url":  item.URL,
		"data": map[string]any{"avatar": item.URL},
	})
}

// trimAvatarHistory 超出保留条数时清理最旧的记录与源文件。
func (srv *Server) trimAvatarHistory(ctx context.Context, userID int, keepURL string) {
	removed, err := srv.store.TrimAvatars(ctx, userID, 20, keepURL)
	if err != nil {
		log.Printf("[avatar] 裁剪头像历史失败: %v", err)
		return
	}
	for _, item := range removed {
		srv.deleteAvatarObject(ctx, item)
	}
}

// deleteAvatarObject 删除头像对应的源文件。
// 存储类型可能被后台改过，因此按记录里保存的 provider 判断：
// local 直接删本地磁盘；其余仅在当前配置与记录一致时才删，避免误删到别的桶。
func (srv *Server) deleteAvatarObject(ctx context.Context, item store.AvatarHistory) {
	if item.ObjectKey == "" {
		return
	}
	if item.Provider == "" || item.Provider == "local" {
		if err := storage.NewLocal(UploadDir()).Delete(ctx, item.ObjectKey); err != nil {
			log.Printf("[avatar] 删除本地头像失败 %s: %v", item.ObjectKey, err)
		}
		return
	}
	up, err := srv.uploader(ctx)
	if err != nil {
		log.Printf("[avatar] 当前存储配置不可用，跳过清理 %s: %v", item.ObjectKey, err)
		return
	}
	if up.Kind() != item.Provider {
		log.Printf("[avatar] 存储类型已变更（%s → %s），跳过清理 %s", item.Provider, up.Kind(), item.ObjectKey)
		return
	}
	if err := up.Delete(ctx, item.ObjectKey); err != nil {
		log.Printf("[avatar] 删除远端头像失败 %s: %v", item.ObjectKey, err)
	}
}

// parseIntQuery 解析整型查询参数。
func parseIntQuery(r *http.Request, name string) (int, bool) {
	raw := strings.TrimSpace(r.URL.Query().Get(name))
	if raw == "" {
		return 0, false
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return 0, false
	}
	return n, true
}
