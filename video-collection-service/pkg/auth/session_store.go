package auth

import (
	"context"
	"encoding/json"
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

// Save 以 JSON 形式写入 Redis，并带上与会话有效期一致的 TTL，过期自动清理。
func (rs *RedisSessionStore) Save(ctx context.Context, token string, s Session, ttl time.Duration) error {
	if ttl <= 0 {
		ttl = time.Minute
	}
	raw, err := json.Marshal(s)
	if err != nil {
		return err
	}
	return rs.client.Set(ctx, rs.sessionKey(token), string(raw), ttl)
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
	return rs.client.Del(ctx, rs.sessionKey(token))
}
