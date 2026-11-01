package api

import (
	"sync"
	"time"
)

// attemptLimiter 进程内的失败次数限流器。
// 用于登录与改密这类「凭据校验」场景：窗口期内失败达到上限后锁定一段时间。
// 单实例足够；多实例部署时各实例独立计数，属可接受的近似限流。
type attemptLimiter struct {
	mu        sync.Mutex
	entries   map[string]*attemptEntry
	max       int
	window    time.Duration
	lockFor   time.Duration
	lastSweep time.Time
}

type attemptEntry struct {
	failures    int
	lockedUntil time.Time
	lastSeen    time.Time
}

func newAttemptLimiter(max int, window, lockFor time.Duration) *attemptLimiter {
	return &attemptLimiter{
		entries:   make(map[string]*attemptEntry),
		max:       max,
		window:    window,
		lockFor:   lockFor,
		lastSweep: time.Now(),
	}
}

// Allow 判断该 key 当前是否允许继续尝试；被锁定时同时返回剩余等待时长。
func (l *attemptLimiter) Allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.sweepLocked()

	e, ok := l.entries[key]
	if !ok {
		return true, 0
	}
	now := time.Now()
	if now.Before(e.lockedUntil) {
		return false, e.lockedUntil.Sub(now)
	}
	if now.Sub(e.lastSeen) > l.window {
		e.failures = 0
	}
	return true, 0
}

// Fail 记录一次失败；达到上限后进入锁定状态并清零计数。
func (l *attemptLimiter) Fail(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	e, ok := l.entries[key]
	if !ok {
		e = &attemptEntry{}
		l.entries[key] = e
	}
	if now.Sub(e.lastSeen) > l.window {
		e.failures = 0
	}
	e.failures++
	e.lastSeen = now
	if e.failures >= l.max {
		e.lockedUntil = now.Add(l.lockFor)
		e.failures = 0
	}
}

// Reset 在成功校验后清除该 key 的失败记录。
func (l *attemptLimiter) Reset(key string) {
	l.mu.Lock()
	delete(l.entries, key)
	l.mu.Unlock()
}

// sweepLocked 定期清理长期未活动的条目，避免内存无限增长（调用方需持锁）。
func (l *attemptLimiter) sweepLocked() {
	now := time.Now()
	if now.Sub(l.lastSweep) < 10*time.Minute {
		return
	}
	l.lastSweep = now
	for key, e := range l.entries {
		if now.After(e.lockedUntil) && now.Sub(e.lastSeen) > l.window {
			delete(l.entries, key)
		}
	}
}

// 登录：同一「账号 + IP」15 分钟内失败 5 次，锁定 15 分钟。
var loginGuard = newAttemptLimiter(5, 15*time.Minute, 15*time.Minute)

// 改密：同一账号 10 分钟内旧密码校验失败 5 次，锁定 10 分钟。
var passwordGuard = newAttemptLimiter(5, 10*time.Minute, 10*time.Minute)

// 验证码发送：同一目标 10 分钟内最多 5 条，超出锁定 10 分钟。
var codeGuard = newAttemptLimiter(5, 10*time.Minute, 10*time.Minute)

// 验证码校验：同一目标 10 分钟内错误 5 次，锁定 10 分钟（验证码本身另有 5 次上限）。
var resetGuard = newAttemptLimiter(5, 10*time.Minute, 10*time.Minute)
