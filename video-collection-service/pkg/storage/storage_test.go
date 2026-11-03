package storage

import (
	"context"
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"video-collection-service/pkg/integration"
)

func TestLocalPutDelete(t *testing.T) {
	dir := t.TempDir()
	up, err := New(integration.Storage{Provider: "local"}, dir)
	if err != nil {
		t.Fatal(err)
	}
	if up.Kind() != "local" {
		t.Fatalf("Kind 应为 local，实际 %s", up.Kind())
	}

	url, err := up.Put(context.Background(), "avatars/a.png", []byte("hello"), "image/png")
	if err != nil {
		t.Fatal(err)
	}
	if url != "/uploads/avatars/a.png" {
		t.Fatalf("本地 URL 不符合预期: %s", url)
	}
	if data, err := os.ReadFile(filepath.Join(dir, "avatars", "a.png")); err != nil || string(data) != "hello" {
		t.Fatalf("文件未落盘: %v %q", err, string(data))
	}

	if err := up.Delete(context.Background(), "avatars/a.png"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "avatars", "a.png")); !os.IsNotExist(err) {
		t.Fatalf("文件应被删除: %v", err)
	}
	// 删除不存在的对象不报错
	if err := up.Delete(context.Background(), "avatars/none.png"); err != nil {
		t.Fatalf("删除不存在的对象应视为成功: %v", err)
	}
}

func TestSafeKeyRejectsTraversal(t *testing.T) {
	dir := t.TempDir()
	up := NewLocal(dir)
	for _, bad := range []string{"../evil.png", "a/../../evil.png", ""} {
		if _, err := up.Put(context.Background(), bad, []byte("x"), ""); err == nil {
			t.Errorf("非法键 %q 应被拒绝", bad)
		}
	}
}

// OSS 使用经典 V1 签名：Authorization: OSS ak:<base64(hmac-sha1)>
// 且恒走虚拟主机式（桶名在 Host、路径只有对象键）。
func TestOSSSignature(t *testing.T) {
	var gotAuth, gotResource, gotHost string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		gotResource = r.URL.Path
		gotHost = r.Host
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	up, err := NewOSS(integration.Storage{
		Provider: "oss",
		// 模拟用户把带桶名的完整域名填进 Endpoint，应被归一化剥掉桶名
		Endpoint:  "http://demo-bucket." + strings.TrimPrefix(srv.URL, "http://"),
		Bucket:    "demo-bucket",
		AccessKey: "ak",
		SecretKey: "sk",
		Prefix:    "uploads",
	})
	if err != nil {
		t.Fatal(err)
	}
	// 虚拟主机式的 Host（demo-bucket.127.0.0.1）无法解析，用代理把请求转发到测试服务器。
	proxyURL, _ := url.Parse(srv.URL)
	up.client = &http.Client{Transport: &http.Transport{Proxy: func(*http.Request) (*url.URL, error) { return proxyURL, nil }}}

	url, err := up.Put(context.Background(), "avatars/a.png", []byte("data"), "image/png")
	if err != nil {
		t.Fatal(err)
	}
	if gotResource != "/uploads/avatars/a.png" {
		t.Fatalf("对象路径不应包含桶名: %s", gotResource)
	}
	if !strings.HasPrefix(gotHost, "demo-bucket.") {
		t.Fatalf("Host 应带桶名前缀: %s", gotHost)
	}
	if !strings.HasPrefix(gotAuth, "OSS ak:") {
		t.Fatalf("Authorization 格式错误: %s", gotAuth)
	}
	if _, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(gotAuth, "OSS ak:")); err != nil {
		t.Fatalf("签名不是合法 base64: %v", err)
	}
	// 桶内对象带上前缀，URL 按 path-style 拼接
	if !strings.HasSuffix(url, "/uploads/avatars/a.png") {
		t.Fatalf("URL 未包含前缀: %s", url)
	}
}

// S3 使用 SigV4：Authorization 里应带 Credential / SignedHeaders / Signature。
func TestS3SigV4(t *testing.T) {
	var auth, payloadHash string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		payloadHash = r.Header.Get("x-amz-content-sha256")
		body, _ := io.ReadAll(r.Body)
		if len(body) != 4 {
			t.Errorf("请求体长度错误: %d", len(body))
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	up, err := NewS3(integration.Storage{
		Provider:  "s3",
		Endpoint:  srv.URL,
		Region:    "us-east-1",
		Bucket:    "b",
		AccessKey: "AK",
		SecretKey: "SK",
		PathStyle: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := up.Put(context.Background(), "k.txt", []byte("data"), "text/plain"); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(auth, "AWS4-HMAC-SHA256 Credential=AK/") {
		t.Fatalf("SigV4 Authorization 格式错误: %s", auth)
	}
	for _, part := range []string{"SignedHeaders=", "Signature="} {
		if !strings.Contains(auth, part) {
			t.Fatalf("Authorization 缺少 %s: %s", part, auth)
		}
	}
	if len(payloadHash) != 64 {
		t.Fatalf("payload hash 应为 64 位十六进制: %q", payloadHash)
	}
}

func TestDeriveRegion(t *testing.T) {
	cases := map[string]string{
		"oss-cn-hangzhou.aliyuncs.com":          "cn-hangzhou",
		"oss-cn-hangzhou-internal.aliyuncs.com": "cn-hangzhou",
		"oss-ap-southeast-1.aliyuncs.com":       "ap-southeast-1",
		"minio.local":                           "us-east-1",
	}
	for host, want := range cases {
		if got := deriveRegion(host); got != want {
			t.Errorf("%s => %s, 期望 %s", host, got, want)
		}
	}
}

func TestNewRejectsUnknownProvider(t *testing.T) {
	if _, err := New(integration.Storage{Provider: "ftp"}, ""); err == nil {
		t.Fatal("未知存储类型应报错")
	}
}
