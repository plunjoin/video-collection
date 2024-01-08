package auth

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	"video-collection-api/pkg/store"
)

const (
	CookieAuthToken = "agg_auth_token"
	SessionDuration = 7 * 24 * time.Hour
)

type Session struct {
	UserID    int
	Username  string
	Role      string
	ExpiresAt time.Time
}

type SessionManager struct {
	mu       sync.RWMutex
	sessions map[string]Session
}

var DefaultSessionManager = &SessionManager{
	sessions: make(map[string]Session),
}

func (sm *SessionManager) CreateSession(user *store.User) string {
	b := make([]byte, 24)
	_, _ = rand.Read(b)
	token := hex.EncodeToString(b)

	sm.mu.Lock()
	sm.sessions[token] = Session{
		UserID:    user.ID,
		Username:  user.Username,
		Role:      user.Role,
		ExpiresAt: time.Now().Add(SessionDuration),
	}
	sm.mu.Unlock()

	return token
}

func (sm *SessionManager) GetSession(token string) (Session, bool) {
	sm.mu.RLock()
	defer sm.mu.RUnlock()

	sess, ok := sm.sessions[token]
	if !ok || time.Now().After(sess.ExpiresAt) {
		return Session{}, false
	}
	return sess, true
}

func (sm *SessionManager) DeleteSession(token string) {
	sm.mu.Lock()
	delete(sm.sessions, token)
	sm.mu.Unlock()
}

func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}

func CheckPassword(hash, password string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

func SetAuthCookie(w http.ResponseWriter, token string) {
	http.SetCookie(w, &http.Cookie{
		Name:     CookieAuthToken,
		Value:    token,
		Path:     "/",
		Expires:  time.Now().Add(SessionDuration),
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
}

func ClearAuthCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     CookieAuthToken,
		Value:    "",
		Path:     "/",
		Expires:  time.Unix(0, 0),
		HttpOnly: true,
	})
}

// GetCurrentUser 从请求 Cookie 或 Header 获取当前已认证的用户
func GetCurrentUser(r *http.Request, s store.Store) *store.User {
	var token string
	if strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") {
		token = strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	} else if c, err := r.Cookie(CookieAuthToken); err == nil && c.Value != "" {
		token = c.Value
	}
	if token == "" {
		return nil
	}

	sess, ok := DefaultSessionManager.GetSession(token)
	if !ok {
		return nil
	}

	user, err := s.GetUserByID(r.Context(), sess.UserID)
	if err != nil || user == nil || user.Status != 1 {
		return nil
	}
	_ = s.RecordActivity(r.Context(), user.ID, time.Now())
	return user
}

// Backend authorization is evaluated against the current database role on every request.
func BackendAllowed(role, method, path string) bool {
	if !store.IsStaff(role) {
		return false
	}
	read := method == http.MethodGet || method == http.MethodHead
	if role == "observer" {
		return read
	}
	if role == "operator" {
		if read {
			return path == "/api/admin/stats" || path == "/api/admin/reviews" || path == "/api/admin/news" || path == "/api/admin/community/posts" || path == "/api/admin/community/comments" || path == "/api/admin/comments"
		}
		return method == http.MethodPost && (path == "/api/admin/videos/save" || path == "/api/admin/news" || path == "/api/admin/community/posts")
	}
	if role == "admin" && !read {
		for _, prefix := range []string{"/api/admin/db", "/api/admin/themes", "/api/admin/players", "/api/admin/site/config", "/api/admin/scheduler"} {
			if strings.HasPrefix(path, prefix) {
				return false
			}
		}
	}
	return true
}

// AdminRequired 验证管理员权限的路由中间件
type auditWriter struct {
	http.ResponseWriter
	status int
}

func (w *auditWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}
func (w *auditWriter) Write(p []byte) (int, error) {
	if w.status == 0 {
		w.WriteHeader(200)
	}
	return w.ResponseWriter.Write(p)
}
func AdminRequired(s store.Store, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := GetCurrentUser(r, s)
		if user == nil || !store.IsStaff(user.Role) {
			if strings.HasPrefix(r.URL.Path, "/api/") {
				w.Header().Set("Content-Type", "application/json; charset=utf-8")
				w.WriteHeader(http.StatusUnauthorized)
				_ = json.NewEncoder(w).Encode(map[string]any{
					"code":  0,
					"error": "未登录或无管理员权限",
				})
				return
			}
			http.Redirect(w, r, "/admin/login", http.StatusFound)
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			aw := &auditWriter{ResponseWriter: w}
			w = aw
			defer func() {
				status := aw.status
				if status == 0 {
					status = 200
				}
				_ = s.RecordAdminOperation(context.WithoutCancel(r.Context()), user.ID, r.Method, r.URL.Path, status)
			}()
		}
		if !BackendAllowed(user.Role, r.Method, r.URL.Path) {
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.WriteHeader(http.StatusForbidden)
			_ = json.NewEncoder(w).Encode(map[string]any{"code": 0, "error": "当前角色无权执行此操作"})
			return
		}

		ctx := context.WithValue(r.Context(), "user", user)
		next(w, r.WithContext(ctx))
	}
}
