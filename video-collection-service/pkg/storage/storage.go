// Package storage 统一文件上传落地：服务端磁盘（local）或 S3 兼容对象存储（s3）。
//
// S3 签名用标准库手写 SigV4，不引入 SDK：单个 PUT/DELETE 足够，且保持单二进制零额外依赖。
// 兼容阿里云 OSS、腾讯云 COS、MinIO、Cloudflare R2、AWS S3 等。
package storage

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"video-collection-service/pkg/integration"
)

// Uploader 上传与删除对象。
type Uploader interface {
	// Kind 返回存储类型：local / s3。
	Kind() string
	// Put 写入对象并返回可访问 URL。
	Put(ctx context.Context, key string, data []byte, contentType string) (string, error)
	// Delete 删除对象；对象不存在视为成功。
	Delete(ctx context.Context, key string) error
	// URL 仅计算可访问地址，不产生写入。
	URL(key string) string
}

// New 按配置构建 Uploader。localRoot 为本地模式下的根目录。
func New(cfg integration.Storage, localRoot string) (Uploader, error) {
	switch strings.ToLower(strings.TrimSpace(cfg.Provider)) {
	case "", "local":
		return NewLocal(localRoot), nil
	case "oss", "aliyun", "aliyun-oss":
		return NewOSS(cfg)
	case "s3", "cos", "r2", "minio", "aws":
		return NewS3(cfg)
	}
	return nil, fmt.Errorf("不支持的存储类型: %s", cfg.Provider)
}

// ---------------------------------------------------------------------------
// 本地磁盘
// ---------------------------------------------------------------------------

// Local 把文件写到服务端磁盘，由 /uploads/ 静态路由对外提供。
type Local struct {
	root string
}

func NewLocal(root string) *Local { return &Local{root: root} }

func (l *Local) Kind() string { return "local" }

func (l *Local) URL(key string) string {
	return "/uploads/" + strings.TrimPrefix(key, "/")
}

func (l *Local) Put(_ context.Context, key string, data []byte, _ string) (string, error) {
	clean, err := safeKey(key)
	if err != nil {
		return "", err
	}
	full := filepath.Join(l.root, filepath.FromSlash(clean))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		return "", err
	}
	if err := os.WriteFile(full, data, 0o644); err != nil {
		return "", err
	}
	return l.URL(clean), nil
}

func (l *Local) Delete(_ context.Context, key string) error {
	clean, err := safeKey(key)
	if err != nil {
		return err
	}
	err = os.Remove(filepath.Join(l.root, filepath.FromSlash(clean)))
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

// ---------------------------------------------------------------------------
// S3 兼容对象存储
// ---------------------------------------------------------------------------

// S3 通过 SigV4 直传对象存储。
type S3 struct {
	endpoint  *url.URL
	bucket    string
	region    string
	accessKey string
	secretKey string
	domain    string
	prefix    string
	pathStyle bool
	client    *http.Client
}

func NewS3(cfg integration.Storage) (*S3, error) {
	raw := strings.TrimSpace(cfg.Endpoint)
	if raw == "" {
		return nil, fmt.Errorf("对象存储 Endpoint 不能为空")
	}
	if !strings.Contains(raw, "://") {
		raw = "https://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return nil, fmt.Errorf("Endpoint 格式不正确: %s", cfg.Endpoint)
	}
	region := strings.TrimSpace(cfg.Region)
	if region == "" {
		region = deriveRegion(u.Host)
	}
	return &S3{
		endpoint:  u,
		bucket:    strings.TrimSpace(cfg.Bucket),
		region:    region,
		accessKey: strings.TrimSpace(cfg.AccessKey),
		secretKey: cfg.SecretKey,
		domain:    strings.TrimRight(strings.TrimSpace(cfg.Domain), "/"),
		prefix:    cfg.NormalizedPrefix(),
		pathStyle: cfg.PathStyle,
		client:    &http.Client{Timeout: 20 * time.Second},
	}, nil
}

func (s *S3) Kind() string { return "s3" }

// objectKey 拼上配置的前缀，避免与桶内其他业务混在一起。
func (s *S3) objectKey(key string) string {
	return s.prefix + strings.TrimPrefix(key, "/")
}

// URL 生成对外可访问地址：优先自定义域名，其次按 path / virtual-host 风格拼接。
func (s *S3) URL(key string) string {
	k := s.objectKey(key)
	if s.domain != "" {
		return s.domain + "/" + escapeKey(k)
	}
	if s.pathStyle {
		return s.endpoint.Scheme + "://" + s.endpoint.Host + "/" + s.bucket + "/" + escapeKey(k)
	}
	return s.endpoint.Scheme + "://" + s.bucket + "." + s.endpoint.Host + "/" + escapeKey(k)
}

func (s *S3) Put(ctx context.Context, key string, data []byte, contentType string) (string, error) {
	if _, err := safeKey(key); err != nil {
		return "", err
	}
	if err := s.do(ctx, http.MethodPut, s.objectKey(key), data, contentType); err != nil {
		return "", err
	}
	return s.URL(key), nil
}

func (s *S3) Delete(ctx context.Context, key string) error {
	if _, err := safeKey(key); err != nil {
		return err
	}
	return s.do(ctx, http.MethodDelete, s.objectKey(key), nil, "")
}

// do 发送一次签名请求。
func (s *S3) do(ctx context.Context, method, objectKey string, body []byte, contentType string) error {
	req, canonicalPath, host, err := s.buildRequest(ctx, method, objectKey, body, contentType)
	if err != nil {
		return err
	}

	now := time.Now().UTC()
	amzDate := now.Format("20060102T150405Z")
	dateStamp := now.Format("20060102")
	payloadHash := hexSHA256(body)

	req.Header.Set("x-amz-date", amzDate)
	req.Header.Set("x-amz-content-sha256", payloadHash)
	req.Host = host

	signedHeaders := "host;x-amz-content-sha256;x-amz-date"
	canonicalHeaders := "host:" + host + "\n" +
		"x-amz-content-sha256:" + payloadHash + "\n" +
		"x-amz-date:" + amzDate + "\n"
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
		signedHeaders += ";content-type"
		canonicalHeaders += "content-type:" + contentType + "\n"
	}
	canonicalHeaders = sortCanonicalHeaders(canonicalHeaders)
	signedHeaders = sortSignedHeaders(signedHeaders)

	canonicalRequest := strings.Join([]string{
		method, canonicalPath, "", canonicalHeaders, signedHeaders, payloadHash,
	}, "\n")

	scope := dateStamp + "/" + s.region + "/s3/aws4_request"
	stringToSign := "AWS4-HMAC-SHA256\n" + amzDate + "\n" + scope + "\n" + hexSHA256([]byte(canonicalRequest))

	signingKey := hmacSHA256([]byte("AWS4"+s.secretKey), dateStamp)
	signingKey = hmacSHA256(signingKey, s.region)
	signingKey = hmacSHA256(signingKey, "s3")
	signingKey = hmacSHA256(signingKey, "aws4_request")
	signature := hex.EncodeToString(hmacSHA256(signingKey, stringToSign))

	req.Header.Set("Authorization", fmt.Sprintf(
		"AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
		s.accessKey, scope, signedHeaders, signature))

	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		_, _ = io.Copy(io.Discard, resp.Body)
		return nil
	}
	detail, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
	if method == http.MethodDelete && resp.StatusCode == http.StatusNotFound {
		return nil
	}
	return fmt.Errorf("对象存储返回 %d: %s", resp.StatusCode, strings.TrimSpace(string(detail)))
}

func (s *S3) buildRequest(ctx context.Context, method, objectKey string, body []byte, contentType string) (*http.Request, string, string, error) {
	var (
		host      string
		rawPath   string
		canonical string
	)
	escapedKey := escapeKey(objectKey)
	if s.pathStyle {
		host = s.endpoint.Host
		canonical = "/" + s.bucket + "/" + escapedKey
		rawPath = canonical
	} else {
		host = s.bucket + "." + s.endpoint.Host
		canonical = "/" + escapedKey
		rawPath = canonical
	}

	u := &url.URL{Scheme: s.endpoint.Scheme, Host: host, Path: "/" + s.bucket + "/" + objectKey}
	if !s.pathStyle {
		u.Path = "/" + objectKey
	}
	u.RawPath = rawPath

	req, err := http.NewRequestWithContext(ctx, method, u.String(), bytes.NewReader(body))
	if err != nil {
		return nil, "", "", err
	}
	// RawPath 已按 S3 规则编码，避免 Go 再次转义造成签名不一致。
	req.URL.RawPath = rawPath
	req.URL.Path = u.Path
	return req, canonical, host, nil
}

// escapeKey 按 S3 规则编码对象键：保留 '/'，其余非 unreserved 字符全部转义。
func escapeKey(key string) string {
	var b strings.Builder
	for i := 0; i < len(key); i++ {
		c := key[i]
		switch {
		case c >= 'A' && c <= 'Z', c >= 'a' && c <= 'z', c >= '0' && c <= '9',
			c == '-', c == '_', c == '.', c == '~', c == '/':
			b.WriteByte(c)
		default:
			fmt.Fprintf(&b, "%%%02X", c)
		}
	}
	return b.String()
}

// safeKey 拒绝绝对路径与上跳，防止写到目录外。
func safeKey(key string) (string, error) {
	trimmed := strings.TrimSpace(key)
	if trimmed == "" {
		return "", fmt.Errorf("对象键不能为空")
	}
	for _, seg := range strings.Split(strings.ReplaceAll(trimmed, "\\", "/"), "/") {
		if seg == ".." {
			return "", fmt.Errorf("非法的对象键: %s", key)
		}
	}
	clean := strings.TrimPrefix(path.Clean("/"+strings.TrimPrefix(trimmed, "/")), "/")
	if clean == "" || clean == "." {
		return "", fmt.Errorf("非法的对象键: %s", key)
	}
	return clean, nil
}

var regionRe = regexp.MustCompile(`oss-([a-z0-9-]+)\.aliyuncs\.com`)

// deriveRegion 从常见 Endpoint 推断签名区域（阿里云 OSS / 腾讯云 COS）。
func deriveRegion(host string) string {
	host = strings.ToLower(host)
	if m := regionRe.FindStringSubmatch(host); len(m) == 2 {
		return strings.TrimSuffix(m[1], "-internal")
	}
	if strings.Contains(host, "myqcloud.com") {
		if i := strings.Index(host, ".cos."); i > 0 {
			rest := host[i+len(".cos."):]
			if j := strings.Index(rest, ".myqcloud.com"); j > 0 {
				return rest[:j]
			}
		}
	}
	return "us-east-1"
}

func hexSHA256(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func hmacSHA256(key []byte, data string) []byte {
	m := hmac.New(sha256.New, key)
	m.Write([]byte(data))
	return m.Sum(nil)
}

// sortCanonicalHeaders 保证 canonical headers 按字典序排列（SigV4 要求）。
func sortCanonicalHeaders(raw string) string {
	lines := strings.Split(strings.TrimRight(raw, "\n"), "\n")
	for i := 1; i < len(lines); i++ {
		for j := i; j > 0 && lines[j] < lines[j-1]; j-- {
			lines[j], lines[j-1] = lines[j-1], lines[j]
		}
	}
	return strings.Join(lines, "\n") + "\n"
}

func sortSignedHeaders(raw string) string {
	parts := strings.Split(raw, ";")
	for i := 1; i < len(parts); i++ {
		for j := i; j > 0 && parts[j] < parts[j-1]; j-- {
			parts[j], parts[j-1] = parts[j-1], parts[j]
		}
	}
	return strings.Join(parts, ";")
}
