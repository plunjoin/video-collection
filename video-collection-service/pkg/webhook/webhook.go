// Package webhook 提供 Webhook 回调采集的验签、防重放与载荷转换能力。
// 验签基于「原始请求体 + HMAC-SHA256」，密钥哈希由存储层持久化，
// 明文密钥仅在创建/轮换时返回一次，本包不接触密钥存储。
package webhook

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// DefaultSignatureHeaders 依次尝试的签名请求头（按优先级）。
var DefaultSignatureHeaders = []string{
	"X-Webhook-Signature",
	"X-Signature-256",
	"X-Signature",
	"X-Hub-Signature-256",
}

// DefaultTimestampHeaders 依次尝试的时间戳请求头（用于防重放窗口校验）。
var DefaultTimestampHeaders = []string{
	"X-Webhook-Timestamp",
	"X-Timestamp",
	"X-Request-Timestamp",
}

// GenerateSecret 生成随机 webhook 密钥（32 字节，64 位十六进制）。
// 明文仅返回给调用方一次，存储时请使用 HashSecret。
func GenerateSecret() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("生成随机密钥失败: %w", err)
	}
	return hex.EncodeToString(b), nil
}

// HashSecret 计算密钥的 SHA-256 十六进制摘要（存储层只保存摘要）。
func HashSecret(secret string) string {
	sum := sha256.Sum256([]byte(secret))
	return hex.EncodeToString(sum[:])
}

// NormalizeSignature 将签名统一为小写十六进制（剥离 sha256= / sha1= 前缀与空白）。
func NormalizeSignature(sig string) string {
	sig = strings.TrimSpace(sig)
	for _, prefix := range []string{"sha256=", "sha1=", "v1="} {
		if len(sig) > len(prefix) && strings.EqualFold(sig[:len(prefix)], prefix) {
			sig = sig[len(prefix):]
			break
		}
	}
	return strings.ToLower(strings.TrimSpace(sig))
}

// ComputeSignature 基于原始请求体计算 HMAC-SHA256 十六进制签名。
func ComputeSignature(secret string, body []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

// VerifySignature 常量时间比对签名。空签名、空密钥或摘要不匹配均返回 false。
func VerifySignature(secret, provided string, body []byte) bool {
	if secret == "" || provided == "" {
		return false
	}
	expected := ComputeSignature(secret, body)
	got := NormalizeSignature(provided)
	if got == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(got), []byte(expected)) == 1
}

// PickSignatureHeader 依次尝试候选签名头，返回第一个非空值。
func PickSignatureHeader(get func(string) string, headers []string) string {
	if len(headers) == 0 {
		headers = DefaultSignatureHeaders
	}
	for _, h := range headers {
		if v := strings.TrimSpace(get(h)); v != "" {
			return v
		}
	}
	return ""
}

// TimestampResult 时间戳校验结果。
type TimestampResult struct {
	Provided  bool      // 请求是否携带了时间戳
	Timestamp time.Time // 解析出的时间戳（Provided 为 false 时为零值）
	Reason    string    // 拒绝原因（为空表示通过）
}

// CheckTimestamp 校验时间戳是否落在容忍窗口内。
// provided=false 或无法解析时返回对应 Reason，由调用方决定是否拒绝。
func CheckTimestamp(get func(string) string, toleranceSec int, now time.Time) TimestampResult {
	raw := ""
	for _, h := range DefaultTimestampHeaders {
		if v := strings.TrimSpace(get(h)); v != "" {
			raw = v
			break
		}
	}
	if raw == "" {
		return TimestampResult{Provided: false}
	}
	sec, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		// 兼容 RFC3339 时间戳
		if t, perr := time.Parse(time.RFC3339, raw); perr == nil {
			return withinTolerance(t, toleranceSec, now)
		}
		return TimestampResult{Provided: true, Reason: "时间戳格式无效（应为 Unix 秒或 RFC3339）"}
	}
	return withinTolerance(time.Unix(sec, 0), toleranceSec, now)
}

func withinTolerance(t time.Time, toleranceSec int, now time.Time) TimestampResult {
	if toleranceSec <= 0 {
		return TimestampResult{Provided: true, Timestamp: t}
	}
	skew := now.Sub(t)
	if skew < -time.Duration(toleranceSec)*time.Second || skew > time.Duration(toleranceSec)*time.Second {
		return TimestampResult{Provided: true, Timestamp: t, Reason: fmt.Sprintf("时间戳超出容忍窗口（±%d 秒）", toleranceSec)}
	}
	return TimestampResult{Provided: true, Timestamp: t}
}

// AllowsEvent 判断事件类型是否命中白名单；白名单为空表示不限制。
func AllowsEvent(events []string, event string) bool {
	if len(events) == 0 {
		return true
	}
	event = strings.TrimSpace(event)
	if event == "" {
		return true
	}
	for _, e := range events {
		if strings.EqualFold(strings.TrimSpace(e), event) {
			return true
		}
	}
	return false
}

// RemoteAddr 从请求中提取客户端 IP（剥离端口，兼容 X-Forwarded-For 首段）。
func RemoteAddr(remote, forwarded string) string {
	if forwarded != "" {
		first := strings.TrimSpace(strings.Split(forwarded, ",")[0])
		if first != "" {
			return first
		}
	}
	if remote == "" {
		return ""
	}
	if i := strings.LastIndex(remote, ":"); i > 0 && strings.Count(remote, ":") == 1 {
		return remote[:i]
	}
	return remote
}
