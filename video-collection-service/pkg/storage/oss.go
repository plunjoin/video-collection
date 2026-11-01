package storage

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"video-collection-service/pkg/integration"
)

// OSS 阿里云对象存储（经典 V1 签名）。
// 与 S3 分开实现：OSS 的 V1 签名只需 HMAC-SHA1，兼容性最好，
// 也不依赖 x-amz-* 头；S3 兼容模式请把 provider 配成 s3。
type OSS struct {
	endpoint  *url.URL
	bucket    string
	accessKey string
	secretKey string
	domain    string
	prefix    string
	pathStyle bool
	client    *http.Client
}

func NewOSS(cfg integration.Storage) (*OSS, error) {
	raw := strings.TrimSpace(cfg.Endpoint)
	if raw == "" {
		return nil, fmt.Errorf("OSS Endpoint 不能为空")
	}
	if !strings.Contains(raw, "://") {
		raw = "https://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return nil, fmt.Errorf("Endpoint 格式不正确: %s", cfg.Endpoint)
	}
	if strings.TrimSpace(cfg.Bucket) == "" {
		return nil, fmt.Errorf("Bucket 不能为空")
	}
	return &OSS{
		endpoint:  u,
		bucket:    strings.TrimSpace(cfg.Bucket),
		accessKey: strings.TrimSpace(cfg.AccessKey),
		secretKey: cfg.SecretKey,
		domain:    strings.TrimRight(strings.TrimSpace(cfg.Domain), "/"),
		prefix:    cfg.NormalizedPrefix(),
		pathStyle: cfg.PathStyle,
		client:    &http.Client{Timeout: 20 * time.Second},
	}, nil
}

func (o *OSS) Kind() string { return "oss" }

func (o *OSS) objectKey(key string) string {
	return o.prefix + strings.TrimPrefix(key, "/")
}

func (o *OSS) URL(key string) string {
	k := o.objectKey(key)
	if o.domain != "" {
		return o.domain + "/" + escapeKey(k)
	}
	if o.pathStyle {
		return o.endpoint.Scheme + "://" + o.endpoint.Host + "/" + o.bucket + "/" + escapeKey(k)
	}
	return o.endpoint.Scheme + "://" + o.bucket + "." + o.endpoint.Host + "/" + escapeKey(k)
}

func (o *OSS) Put(ctx context.Context, key string, data []byte, contentType string) (string, error) {
	if _, err := safeKey(key); err != nil {
		return "", err
	}
	if err := o.do(ctx, http.MethodPut, o.objectKey(key), data, contentType); err != nil {
		return "", err
	}
	return o.URL(key), nil
}

func (o *OSS) Delete(ctx context.Context, key string) error {
	if _, err := safeKey(key); err != nil {
		return err
	}
	return o.do(ctx, http.MethodDelete, o.objectKey(key), nil, "")
}

// do 发送一次 V1 签名请求。
func (o *OSS) do(ctx context.Context, method, objectKey string, body []byte, contentType string) error {
	// V1 签名的 CanonicalizedResource 恒为 /bucket/key，两种访问风格一致，
	// 只有 Host 与请求路径不同。
	resource := "/" + o.bucket + "/" + objectKey
	host := o.bucket + "." + o.endpoint.Host
	reqPath := "/" + objectKey
	if o.pathStyle {
		host = o.endpoint.Host
		reqPath = "/" + o.bucket + "/" + objectKey
	}

	u := &url.URL{Scheme: o.endpoint.Scheme, Host: host, Path: reqPath}
	req, err := http.NewRequestWithContext(ctx, method, u.String(), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Host = host

	date := time.Now().UTC().Format(http.TimeFormat)
	req.Header.Set("Date", date)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	stringToSign := method + "\n" + "" + "\n" + contentType + "\n" + date + "\n" + resource
	mac := hmac.New(sha1.New, []byte(o.secretKey))
	mac.Write([]byte(stringToSign))
	signature := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	req.Header.Set("Authorization", "OSS "+o.accessKey+":"+signature)

	resp, err := o.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		_, _ = io.Copy(io.Discard, resp.Body)
		return nil
	}
	if method == http.MethodDelete && resp.StatusCode == http.StatusNotFound {
		return nil
	}
	detail, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
	return fmt.Errorf("OSS 返回 %d: %s", resp.StatusCode, strings.TrimSpace(string(detail)))
}
