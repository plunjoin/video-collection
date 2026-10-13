package cache

import (
	"context"
	"testing"
	"time"
)

func TestDisabledClientPassthrough(t *testing.T) {
	var c *Client // 未配置 Redis 时的 nil 客户端
	if c.Enabled() {
		t.Fatal("nil 客户端应处于未启用状态")
	}
	if _, ok := c.Get(context.Background(), "k"); ok {
		t.Fatal("未启用时 Get 应返回未命中")
	}
	if err := c.Set(context.Background(), "k", "v", time.Second); err != nil {
		t.Fatalf("未启用时 Set 应静默成功: %v", err)
	}
	if err := c.Del(context.Background(), "k"); err != nil {
		t.Fatalf("未启用时 Del 应静默成功: %v", err)
	}
	if err := c.Ping(context.Background()); err != nil {
		t.Fatalf("未启用时 Ping 应静默成功: %v", err)
	}
	if err := c.Close(); err != nil {
		t.Fatalf("未启用时 Close 应静默成功: %v", err)
	}
}

func TestNamespaceNilSafety(t *testing.T) {
	var c *Client
	ns := c.Namespace("videos", time.Minute)
	if ns.Enabled() {
		t.Fatal("nil 客户端的命名空间应处于未启用状态")
	}
	payload, err := ns.Fetch(context.Background(), "p1", 0, func(ctx context.Context) ([]byte, error) {
		return []byte("fresh"), nil
	})
	if err != nil {
		t.Fatalf("未启用时 Fetch 应透传 produce: %v", err)
	}
	if string(payload) != "fresh" {
		t.Fatalf("透传结果应为 fresh，实际为 %q", payload)
	}
	ns.Invalidate(context.Background()) // 不应 panic
}

func TestConfigFromEnv(t *testing.T) {
	t.Setenv("REDIS_ADDR", " 127.0.0.1:6379 ")
	t.Setenv("REDIS_PASSWORD", "secret")
	t.Setenv("REDIS_DB", "3")
	t.Setenv("REDIS_PREFIX", "vcx")
	cfg := ConfigFromEnv()
	if cfg.Addr != "127.0.0.1:6379" || cfg.Password != "secret" || cfg.DB != 3 || cfg.Prefix != "vcx" {
		t.Fatalf("环境变量解析不符合预期: %+v", cfg)
	}
}
