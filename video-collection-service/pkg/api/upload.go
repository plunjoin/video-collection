package api

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"video-collection-service/pkg/auth"
)

const (
	// 头像单文件上限 2MB；请求体留 512KB 余量给 multipart 头。
	avatarMaxBytes = 2 << 20
	avatarBodySlack = 512 << 10
	uploadURLPrefix = "/uploads"
)

// UploadDir 返回上传根目录，可用 UPLOAD_DIR 覆盖（默认 data/uploads，已在 .gitignore 内）。
func UploadDir() string {
	if dir := strings.TrimSpace(os.Getenv("UPLOAD_DIR")); dir != "" {
		return dir
	}
	return filepath.Join("data", "uploads")
}

// registerUploadRoutes 托管 /uploads/ 静态目录（头像等用户上传文件）。
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

// handleUploadAvatar 接收 multipart 头像，落盘后把相对 URL 写回用户资料。
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

	head := make([]byte, 512)
	n, err := io.ReadFull(file, head)
	if err != nil && err != io.ErrUnexpectedEOF && err != io.EOF {
		errorResponse(w, http.StatusBadRequest, "读取图片失败")
		return
	}
	head = head[:n]
	ext, ok := avatarExt(http.DetectContentType(head))
	if !ok {
		errorResponse(w, http.StatusBadRequest, "仅支持 JPG / PNG / WebP / GIF 图片")
		return
	}

	dir := filepath.Join(UploadDir(), "avatars")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		errorResponse(w, http.StatusInternalServerError, "头像目录不可写")
		return
	}
	name := fmt.Sprintf("%d-%d-%s.%s", u.ID, time.Now().UnixNano(), randomHex(4), ext)
	path := filepath.Join(dir, name)

	out, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "头像保存失败")
		return
	}
	if _, err = out.Write(head); err == nil {
		_, err = io.Copy(out, io.LimitReader(file, avatarMaxBytes+1))
	}
	closeErr := out.Close()
	if err != nil || closeErr != nil {
		_ = os.Remove(path)
		errorResponse(w, http.StatusInternalServerError, "头像保存失败")
		return
	}
	if info, statErr := os.Stat(path); statErr != nil || info.Size() > avatarMaxBytes {
		_ = os.Remove(path)
		errorResponse(w, http.StatusRequestEntityTooLarge, "图片不能超过 2MB")
		return
	}

	avatarURL := uploadURLPrefix + "/avatars/" + name
	if err := srv.store.UpdateAvatar(r.Context(), u.ID, avatarURL); err != nil {
		_ = os.Remove(path)
		errorResponse(w, http.StatusInternalServerError, "头像保存失败，请稍后重试")
		return
	}
	removeUploadedAvatar(u.Avatar, avatarURL)

	name2 := strings.TrimSpace(u.Nickname)
	if name2 == "" {
		name2 = u.Username
	}
	srv.logSystemActor(r, u.ID, name2, "info", "auth", "更新头像", map[string]any{"username": u.Username})

	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  "头像已更新",
		"url":  avatarURL,
		"data": map[string]any{"avatar": avatarURL},
	})
}

// removeUploadedAvatar 清理被替换掉的旧头像；只处理本服务托管的 /uploads/ 路径，
// 外链头像与装扮头像不受影响。
func removeUploadedAvatar(oldURL, keepURL string) {
	if oldURL == "" || oldURL == keepURL || !strings.HasPrefix(oldURL, uploadURLPrefix+"/avatars/") {
		return
	}
	name := strings.TrimPrefix(oldURL, uploadURLPrefix+"/avatars/")
	if name == "" || strings.ContainsAny(name, `/\`) || strings.Contains(name, "..") {
		return
	}
	_ = os.Remove(filepath.Join(UploadDir(), "avatars", name))
}
