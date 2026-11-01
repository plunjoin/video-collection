package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	"video-collection-service/pkg/store"
)

const (
	CookieAuthToken = "agg_auth_token"
	SessionDuration = 7 * 24 * time.Hour
)

// Session 表示一次登录会话。结构体可 JSON 序列化，支持写入 Redis 实现分布式会话。
type Session struct {
	UserID    int       `json:"user_id"`
	Username  string    `json:"username"`
	Role      string    `json:"role"`
	ExpiresAt time.Time `json:"expires_at"`
	// CreatedAt / IP / UserAgent 用于「登录设备」列表展示，旧会话缺省为零值。
	CreatedAt time.Time `json:"created_at"`
	IP        string    `json:"ip"`
	UserAgent string    `json:"user_agent"`
}

// SessionMeta 登录时采集的设备信息。
type SessionMeta struct {
	IP        string
	UserAgent string
}

// SessionView 对外暴露的会话视图：不返回令牌本身，用短 ID 供吊销时定位。
type SessionView struct {
	ID        string    `json:"id"`
	Current   bool      `json:"current"`
	IP        string    `json:"ip"`
	UserAgent string    `json:"user_agent"`
	CreatedAt time.Time `json:"created_at"`
	ExpiresAt time.Time `json:"expires_at"`
}

// TokenSession 内部使用的「令牌 + 会话」组合，仅在按用户枚举会话时使用。
type TokenSession struct {
	Token   string
	Session Session
}

// SessionManager 会话管理器。
// 默认使用进程内内存存储；通过 SetStore 可切换为 Redis（radix）分布式存储，
// 支撑多实例部署与重启免登录，Redis 故障时自动降级回内存存储。
type SessionManager struct {
	mu       sync.RWMutex
	store    SessionStore // 可选外置存储，nil 表示纯内存模式
	sessions map[string]Session
}

var DefaultSessionManager = &SessionManager{
	sessions: make(map[string]Session),
}

// SetStore 切换外置会话存储（传入 nil 恢复纯内存模式）。实现见 session_store.go。
func (sm *SessionManager) SetStore(s SessionStore) {
	sm.mu.Lock()
	sm.store = s
	sm.mu.Unlock()
}

// CreateSession 为用户创建新会话并返回令牌。
func (sm *SessionManager) CreateSession(user *store.User, meta SessionMeta) string {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		log.Printf("[auth] 生成会话令牌失败: %v", err)
		return ""
	}
	token := hex.EncodeToString(b)

	now := time.Now()
	sess := Session{
		UserID:    user.ID,
		Username:  user.Username,
		Role:      user.Role,
		ExpiresAt: now.Add(SessionDuration),
		CreatedAt: now,
		IP:        meta.IP,
		UserAgent: truncateText(meta.UserAgent, 255),
	}

	sm.mu.RLock()
	store := sm.store
	sm.mu.RUnlock()

	if store != nil {
		if err := store.Save(context.Background(), token, sess, time.Until(sess.ExpiresAt)); err == nil {
			return token
		} else {
			log.Printf("[auth] 会话写入 Redis 失败，降级为内存存储: %v", err)
		}
	}

	sm.mu.Lock()
	sm.sessions[token] = sess
	sm.mu.Unlock()
	return token
}

// GetSession 查询会话；外置存储未命中时会回退查询内存（覆盖降级写入的场景）。
func (sm *SessionManager) GetSession(token string) (Session, bool) {
	sm.mu.RLock()
	store := sm.store
	sm.mu.RUnlock()

	if store != nil {
		if sess, ok := store.Load(context.Background(), token); ok && time.Now().Before(sess.ExpiresAt) {
			return sess, true
		}
	}

	sm.mu.RLock()
	defer sm.mu.RUnlock()
	sess, ok := sm.sessions[token]
	if !ok || time.Now().After(sess.ExpiresAt) {
		return Session{}, false
	}
	return sess, true
}

// DeleteSession 销毁会话（同时清理外置存储与内存中的副本）。
func (sm *SessionManager) DeleteSession(token string) {
	sm.mu.RLock()
	store := sm.store
	sm.mu.RUnlock()

	if store != nil {
		if err := store.Delete(context.Background(), token); err != nil {
			log.Printf("[auth] 从 Redis 删除会话失败: %v", err)
		}
	}

	sm.mu.Lock()
	delete(sm.sessions, token)
	sm.mu.Unlock()
}

// SessionID 由令牌派生稳定的短标识，供前端标记或吊销某条会话，避免直接暴露令牌。
func SessionID(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])[:12]
}

func truncateText(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max]
}

func toSessionView(token string, s Session) SessionView {
	return SessionView{
		ID:        SessionID(token),
		IP:        s.IP,
		UserAgent: s.UserAgent,
		CreatedAt: s.CreatedAt,
		ExpiresAt: s.ExpiresAt,
	}
}

// ListUserSessions 列出某个用户当前有效的全部会话（外置存储 + 内存降级副本）。
func (sm *SessionManager) ListUserSessions(userID int) []SessionView {
	now := time.Now()
	out := make([]SessionView, 0, 4)
	seen := make(map[string]bool)

	sm.mu.RLock()
	st := sm.store
	sm.mu.RUnlock()
	if st != nil {
		items, err := st.ListByUser(context.Background(), userID)
		if err != nil {
			log.Printf("[auth] 读取用户会话列表失败: %v", err)
		}
		for _, it := range items {
			if now.After(it.Session.ExpiresAt) || seen[it.Token] {
				continue
			}
			seen[it.Token] = true
			out = append(out, toSessionView(it.Token, it.Session))
		}
	}

	sm.mu.RLock()
	for token, sess := range sm.sessions {
		if sess.UserID != userID || now.After(sess.ExpiresAt) || seen[token] {
			continue
		}
		out = append(out, toSessionView(token, sess))
	}
	sm.mu.RUnlock()

	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out
}

// RevokeSession 按会话 ID 吊销某个用户的一条会话，返回是否命中。
func (sm *SessionManager) RevokeSession(userID int, id string) bool {
	if id == "" {
		return false
	}
	revoked := false

	sm.mu.RLock()
	st := sm.store
	sm.mu.RUnlock()
	if st != nil {
		items, err := st.ListByUser(context.Background(), userID)
		if err != nil {
			log.Printf("[auth] 吊销会话前读取列表失败: %v", err)
		}
		for _, it := range items {
			if SessionID(it.Token) != id {
				continue
			}
			if err := st.Delete(context.Background(), it.Token); err != nil {
				log.Printf("[auth] 吊销会话失败: %v", err)
				continue
			}
			revoked = true
		}
	}

	sm.mu.Lock()
	for token, sess := range sm.sessions {
		if sess.UserID == userID && SessionID(token) == id {
			delete(sm.sessions, token)
			revoked = true
		}
	}
	sm.mu.Unlock()
	return revoked
}

// RevokeOtherSessions 吊销该用户除 keepToken 外的全部会话，返回吊销数量。
func (sm *SessionManager) RevokeOtherSessions(userID int, keepToken string) int {
	count := 0

	sm.mu.RLock()
	st := sm.store
	sm.mu.RUnlock()
	if st != nil {
		n, err := st.DeleteByUser(context.Background(), userID, keepToken)
		if err != nil {
			log.Printf("[auth] 批量吊销会话失败: %v", err)
		}
		count += n
	}

	sm.mu.Lock()
	for token, sess := range sm.sessions {
		if sess.UserID == userID && token != keepToken {
			delete(sm.sessions, token)
			count++
		}
	}
	sm.mu.Unlock()
	return count
}

// TokenFromRequest 提取请求携带的会话令牌（Bearer 优先，其次 Cookie）。
func TokenFromRequest(r *http.Request) string {
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		return strings.TrimSpace(strings.TrimPrefix(h, "Bearer "))
	}
	if c, err := r.Cookie(CookieAuthToken); err == nil {
		return c.Value
	}
	return ""
}

// ClientIP 取真实客户端 IP，兼容反向代理透传的 X-Forwarded-For / X-Real-IP。
func ClientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if first, _, ok := strings.Cut(xff, ","); ok {
			return strings.TrimSpace(first)
		}
		return strings.TrimSpace(xff)
	}
	if ip := strings.TrimSpace(r.Header.Get("X-Real-IP")); ip != "" {
		return ip
	}
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
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
		for _, prefix := range []string{"/api/admin/db", "/api/admin/themes", "/api/admin/players", "/api/admin/site/config", "/api/admin/scheduler", "/api/admin/integrations"} {
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

// SuperAdminRequired 仅允许超级管理员访问的路由中间件（破坏性操作专用）。
// 在 AdminRequired 的基础上追加角色校验，并保持管理操作审计。
func SuperAdminRequired(s store.Store, next http.HandlerFunc) http.HandlerFunc {
	return AdminRequired(s, func(w http.ResponseWriter, r *http.Request) {
		user := GetCurrentUser(r, s)
		if user == nil || user.Role != "super_admin" {
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.WriteHeader(http.StatusForbidden)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"code":  0,
				"error": "该操作仅限超级管理员执行",
			})
			return
		}
		next(w, r)
	})
}
