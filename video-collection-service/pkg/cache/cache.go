// Package cache 基于 mediocregopher/radix/v4 的 Redis 缓存层。
//
// 设计目标：
//   - Redis 未配置（未设置 REDIS_ADDR）或连接失败时，所有读写自动降级为透传，
//     服务零依赖可用；
//   - 采用「命名空间 + 代份（generation）」失效模型：写操作只需 INCR 一次代份键，
//     即可让该命名空间下全部缓存立即过期，避免 SCAN+DEL 的大键扫描；
//   - 会话存储同样可切换至 Redis，支撑多实例部署时登录态共享。
package cache

import (
	"context"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/mediocregopher/radix/v4"
)

// Config Redis 连接配置，均从环境变量读取：
//
//	REDIS_ADDR     地址（如 127.0.0.1:6379；未设置则完全禁用缓存与会话外置）
//	REDIS_PASSWORD 密码（可选）
//	REDIS_DB       库索引（可选，默认 0）
//	REDIS_PREFIX   键前缀（可选，默认 vc，用于多套服务共用一个 Redis 实例）
type Config struct {
	Addr     string
	Password string
	DB       int
	Prefix   string
}

// ConfigFromEnv 从环境变量构造 Redis 配置。
func ConfigFromEnv() Config {
	cfg := Config{
		Addr:     strings.TrimSpace(os.Getenv("REDIS_ADDR")),
		Password: os.Getenv("REDIS_PASSWORD"),
		Prefix:   strings.TrimSpace(os.Getenv("REDIS_PREFIX")),
	}
	if cfg.Prefix == "" {
		cfg.Prefix = "vc"
	}
	if v := strings.TrimSpace(os.Getenv("REDIS_DB")); v != "" {
		if db, err := strconv.Atoi(v); err == nil && db >= 0 {
			cfg.DB = db
		}
	}
	return cfg
}

// Client 封装 radix 连接池。Enabled() 为 false 时表示未接入 Redis，缓存全链路降级。
type Client struct {
	client radix.Client
	cfg    Config
}

// Connect 尝试连接 Redis。
// 未配置 REDIS_ADDR 或连接失败时返回 (nil, nil)，由调用方以降级模式继续运行。
func Connect(ctx context.Context, cfg Config) (*Client, error) {
	if cfg.Addr == "" {
		return nil, nil
	}
	// AUTH / SELECT 由 radix.Dialer 在每次新建底层连接时自动完成。
	dialer := radix.Dialer{AuthPass: cfg.Password}
	if cfg.DB > 0 {
		dialer.SelectDB = strconv.Itoa(cfg.DB)
	}
	client, err := (radix.PoolConfig{
		Size:         16,
		PingInterval: 30 * time.Second,
		Dialer:       dialer,
	}).New(ctx, "tcp", cfg.Addr)
	if err != nil {
		return nil, fmt.Errorf("连接 Redis %s 失败: %w", cfg.Addr, err)
	}
	c := &Client{client: client, cfg: cfg}
	if err := c.Ping(ctx); err != nil {
		_ = client.Close()
		return nil, err
	}
	return c, nil
}

// Enabled 表示 Redis 缓存是否可用。
func (c *Client) Enabled() bool { return c != nil }

// Close 释放连接池。
func (c *Client) Close() error {
	if !c.Enabled() {
		return nil
	}
	return c.client.Close()
}

// Ping 探测 Redis 连通性。
func (c *Client) Ping(ctx context.Context) error {
	if !c.Enabled() {
		return nil
	}
	return c.do(ctx, radix.Cmd(nil, "PING"))
}

// do 统一加上 2 秒超时后透传至连接池，防止慢 Redis 拖垮请求线程。
func (c *Client) do(ctx context.Context, a radix.Action) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	return c.client.Do(ctx, a)
}

// Get 读取字符串值；键不存在或 Redis 异常均返回 ("", false)，调用方按未命中处理。
func (c *Client) Get(ctx context.Context, key string) (string, bool) {
	if !c.Enabled() {
		return "", false
	}
	var out string
	if err := c.do(ctx, radix.Cmd(&out, "GET", c.key(key))); err != nil {
		return "", false
	}
	return out, true
}

// SetJSON 写入 JSON 序列化结果并设置 TTL。
func (c *Client) SetJSON(ctx context.Context, key string, value any, ttl time.Duration) error {
	if !c.Enabled() {
		return nil
	}
	return c.Set(ctx, key, value, ttl)
}

// Set 写入字符串值并设置 TTL（ttl<=0 表示永不过期，仅用于会话等场景，由业务自行清理）。
func (c *Client) Set(ctx context.Context, key string, value any, ttl time.Duration) error {
	if !c.Enabled() {
		return nil
	}
	args := []string{c.key(key), fmt.Sprint(value)}
	if ttl > 0 {
		args = append(args, "EX", strconv.FormatInt(int64(ttl/time.Second), 10))
	}
	return c.do(ctx, radix.Cmd(nil, "SET", args...))
}

// Del 删除一组键，忽略不存在的情况。
func (c *Client) Del(ctx context.Context, keys ...string) error {
	if !c.Enabled() || len(keys) == 0 {
		return nil
	}
	full := make([]string, 0, len(keys))
	for _, k := range keys {
		full = append(full, c.key(k))
	}
	return c.do(ctx, radix.Cmd(nil, "DEL", full...))
}

// Incr 将键值自增并返回新值（不存在时从 0 开始）。
func (c *Client) Incr(ctx context.Context, key string) (int64, error) {
	var n int64
	if err := c.do(ctx, radix.Cmd(&n, "INCR", c.key(key))); err != nil {
		return 0, err
	}
	return n, nil
}

// key 为业务键加上实例级前缀，避免与其他服务共用一个 Redis 时冲突。
func (c *Client) key(k string) string {
	return c.cfg.Prefix + ":" + k
}

// genKey 命名空间代份键。
func (c *Client) genKey(ns string) string { return "gen:" + ns }

// nsKey 命名空间内的数据键，嵌入代份号实现批量失效。
func (c *Client) nsKey(ns string, gen int64, key string) string {
	return fmt.Sprintf("ns:%s:g%d:%s", ns, gen, key)
}

// logCacheErr 缓存读写失败只影响性能不影响正确性，降级为 debug 级日志。
func logCacheErr(op, key string, err error) {
	log.Printf("[cache] %s %s 失败（已降级）: %v", op, key, err)
}

// Namespace 表示一个带默认 TTL 的缓存命名空间。
type Namespace struct {
	client *Client
	name   string
	ttl    time.Duration
}

// Namespace 创建（或返回 nil，当客户端不可用时）一个命名空间。
// 命名空间上的全部操作在客户端不可用时均为透传，调用方无需判空。
func (c *Client) Namespace(name string, ttl time.Duration) *Namespace {
	if !c.Enabled() {
		return nil
	}
	return &Namespace{client: c, name: name, ttl: ttl}
}

// Name 返回命名空间名称。
func (ns *Namespace) Name() string {
	if ns == nil {
		return ""
	}
	return ns.name
}

// Generation 返回当前命名空间代份（Invalidate 的 INCR 计数）。Redis 不可用时返回 0。
func (ns *Namespace) Generation(ctx context.Context) int64 {
	if !ns.Enabled() {
		return 0
	}
	var out string
	if err := ns.client.do(ctx, radix.Cmd(&out, "GET", ns.client.genKey(ns.name))); err != nil {
		return 0
	}
	gen64, convErr := strconv.ParseInt(out, 10, 64)
	if convErr != nil {
		return 0
	}
	return gen64
}

// Fetch 缓存读：命中直接返回；未命中时执行 produce 生成并回写 Redis。
// Redis 不可用时等价于直接执行 produce。
func (ns *Namespace) Fetch(ctx context.Context, key string, ttl time.Duration, produce func(context.Context) ([]byte, error)) ([]byte, error) {
	if !ns.Enabled() {
		return produce(ctx)
	}
	if ttl <= 0 {
		ttl = ns.ttl
	}
	gen := ns.Generation(ctx)
	cacheKey := ns.client.nsKey(ns.name, gen, key)
	if raw, ok := ns.client.Get(ctx, cacheKey); ok {
		return []byte(raw), nil
	}
	payload, err := produce(ctx)
	if err != nil {
		return nil, err
	}
	if setErr := ns.client.Set(ctx, cacheKey, string(payload), ttl); setErr != nil {
		logCacheErr("SET", cacheKey, setErr)
	}
	return payload, nil
}

// Invalidate 递增命名空间代份，使该命名空间下所有缓存键立即失效（旧键等待 TTL 自然回收）。
func (ns *Namespace) Invalidate(ctx context.Context) {
	if !ns.Enabled() {
		return
	}
	if _, err := ns.client.Incr(ctx, ns.client.genKey(ns.name)); err != nil {
		logCacheErr("INCR", ns.client.genKey(ns.name), err)
	}
}

// Enabled 命名空间是否可用。
func (ns *Namespace) Enabled() bool { return ns != nil && ns.client.Enabled() }
