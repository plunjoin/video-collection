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
	if c, err := r.Cookie(CookieAuthToken); err == nil && c.Value != "" {
		token = c.Value
	}
	if token == "" {
		authHeader := r.Header.Get("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}
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
	return user
}

// AdminRequired 验证管理员权限的路由中间件
func AdminRequired(s store.Store, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := GetCurrentUser(r, s)
		if user == nil || user.Role != "admin" {
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

		ctx := context.WithValue(r.Context(), "user", user)
		next(w, r.WithContext(ctx))
	}
}
