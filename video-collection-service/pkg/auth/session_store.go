package auth

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"video-collection-service/pkg/cache"
)

// SessionStore 会话存储抽象。
// 默认进程内内存存储；配置 Redis (radix) 后使用 RedisSessionStore，
// 实现多实例部署时的登录态共享与服务重启后免登录。
type SessionStore interface {
	// Save 写入会话，ttl 为会话剩余有效期。
	Save(ctx context.Context, token string, s Session, ttl time.Duration) error
	// Load 读取会话，不存在时返回 (Session{}, false)。
	Load(ctx context.Context, token string) (Session, bool)
	// Delete 删除会话。
	Delete(ctx context.Context, token string) error
	// ListByUser 列出某用户当前有效的会话，含令牌，仅供服务端内部使用。
	ListByUser(ctx context.Context, userID int) ([]TokenSession, error)
	// DeleteByUser 吊销某用户除 keepToken 外的全部会话，返回吊销数量。
	DeleteByUser(ctx context.Context, userID int, keepToken string) (int, error)
}

// RedisSessionStore 基于 radix (Redis) 的分布式会话存储。
type RedisSessionStore struct {
	client *cache.Client
}

// NewRedisSessionStore 创建 Redis 会话存储。
func NewRedisSessionStore(c *cache.Client) *RedisSessionStore {
	return &RedisSessionStore{client: c}
}

// Enabled 表示 Redis 客户端是否可用。
func (rs *RedisSessionStore) Enabled() bool { return rs.client.Enabled() }

func (rs *RedisSessionStore) sessionKey(token string) string { return "sess:" + token }

// userKey 维护「用户 → 会话令牌」集合，支撑登录设备列表与按用户批量吊销。
func (rs *RedisSessionStore) userKey(userID int) string {
	return "usess:" + strconv.Itoa(userID)
}

// Save 以 JSON 形式写入 Redis，并带上与会话有效期一致的 TTL，过期自动清理。
func (rs *RedisSessionStore) Save(ctx context.Context, token string, s Session, ttl time.Duration) error {
	if ttl <= 0 {
		ttl = time.Minute
	}
	raw, err := json.Marshal(s)
	if err != nil {
		return err
	}
	if err := rs.client.Set(ctx, rs.sessionKey(token), string(raw), ttl); err != nil {
		return err
	}
	// 索引的 TTL 统一对齐会话上限，成员过期由 ListByUser 惰性清理。
	if err := rs.client.SAdd(ctx, rs.userKey(s.UserID), token); err != nil {
		return err
	}
	return rs.client.Expire(ctx, rs.userKey(s.UserID), SessionDuration)
}

// Load 从 Redis 读取会话。
func (rs *RedisSessionStore) Load(ctx context.Context, token string) (Session, bool) {
	raw, ok := rs.client.Get(ctx, rs.sessionKey(token))
	if !ok {
		return Session{}, false
	}
	var s Session
	if err := json.Unmarshal([]byte(raw), &s); err != nil {
		return Session{}, false
	}
	return s, true
}

// Delete 从 Redis 删除会话（登出 / 踢下线）。
func (rs *RedisSessionStore) Delete(ctx context.Context, token string) error {
	if s, ok := rs.Load(ctx, token); ok {
		_ = rs.client.SRem(ctx, rs.userKey(s.UserID), token)
	}
	return rs.client.Del(ctx, rs.sessionKey(token))
}

// ListByUser 通过用户会话索引枚举有效会话，并顺带清理已过期的索引成员。
func (rs *RedisSessionStore) ListByUser(ctx context.Context, userID int) ([]TokenSession, error) {
	tokens, err := rs.client.SMembers(ctx, rs.userKey(userID))
	if err != nil {
		return nil, err
	}
	now := time.Now()
	out := make([]TokenSession, 0, len(tokens))
	stale := make([]string, 0, len(tokens))
	for _, token := range tokens {
		s, ok := rs.Load(ctx, token)
		if !ok || now.After(s.ExpiresAt) {
			stale = append(stale, token)
			continue
		}
		out = append(out, TokenSession{Token: token, Session: s})
	}
	if len(stale) > 0 {
		_ = rs.client.SRem(ctx, rs.userKey(userID), stale...)
	}
	return out, nil
}

// DeleteByUser 吊销某用户除 keepToken 外的全部会话。
func (rs *RedisSessionStore) DeleteByUser(ctx context.Context, userID int, keepToken string) (int, error) {
	tokens, err := rs.client.SMembers(ctx, rs.userKey(userID))
	if err != nil {
		return 0, err
	}
	removed := 0
	deleted := make([]string, 0, len(tokens))
	for _, token := range tokens {
		if token == keepToken {
			continue
		}
		if err := rs.client.Del(ctx, rs.sessionKey(token)); err != nil {
			return removed, err
		}
		deleted = append(deleted, token)
		removed++
	}
	if len(deleted) > 0 {
		_ = rs.client.SRem(ctx, rs.userKey(userID), deleted...)
	}
	return removed, nil
}
