package rag

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"strings"
	"time"
)

// EmbeddingProvider 可插拔嵌入模型（本地假向量或远程 API）。
type EmbeddingProvider interface {
	Dimensions() int
	Name() string
	Embed(ctx context.Context, texts []string) ([][]float32, error)
}

// NewEmbeddingProviderFromEnv 无 API Key 时使用确定性本地向量，保证离线可跑通。
func NewEmbeddingProviderFromEnv() EmbeddingProvider {
	provider := strings.ToLower(strings.TrimSpace(os.Getenv("RAG_EMBEDDING_PROVIDER")))
	dim := envInt("RAG_EMBEDDING_DIM", 384)
	switch provider {
	case "openai":
		key := strings.TrimSpace(os.Getenv("OPENAI_API_KEY"))
		if key == "" {
			return &FakeEmbeddingProvider{dim: dim}
		}
		model := strings.TrimSpace(os.Getenv("OPENAI_EMBEDDING_MODEL"))
		if model == "" {
			model = "text-embedding-3-small"
		}
		return &OpenAIEmbeddingProvider{
			apiKey:  key,
			model:   model,
			dim:     dim,
			baseURL: strings.TrimRight(strings.TrimSpace(os.Getenv("OPENAI_BASE_URL")), "/"),
			client:  &http.Client{Timeout: 45 * time.Second},
		}
	default:
		return &FakeEmbeddingProvider{dim: dim}
	}
}

func envInt(key string, def int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return def
	}
	var n int
	if _, err := fmt.Sscanf(raw, "%d", &n); err != nil || n <= 0 {
		return def
	}
	return n
}

// FakeEmbeddingProvider 基于文本哈希的确定性伪向量（仅用于开发与测试）。
type FakeEmbeddingProvider struct {
	dim int
}

func (f *FakeEmbeddingProvider) Dimensions() int {
	if f.dim <= 0 {
		return 384
	}
	return f.dim
}

func (f *FakeEmbeddingProvider) Name() string { return "fake" }

func (f *FakeEmbeddingProvider) Embed(ctx context.Context, texts []string) ([][]float32, error) {
	out := make([][]float32, len(texts))
	for i, t := range texts {
		out[i] = hashEmbedding(t, f.Dimensions())
	}
	return out, nil
}

func hashEmbedding(text string, dim int) []float32 {
	vec := make([]float32, dim)
	h := sha256.Sum256([]byte(text))
	for i := 0; i < dim; i++ {
		// 用哈希字节循环填充并映射到 [-1,1]
		b := h[i%len(h)]
		vec[i] = (float32(int(b)-128)) / 128.0
	}
	normalize(vec)
	return vec
}

func normalize(v []float32) {
	var sum float64
	for _, x := range v {
		sum += float64(x) * float64(x)
	}
	if sum == 0 {
		return
	}
	inv := float32(1.0 / math.Sqrt(sum))
	for i := range v {
		v[i] *= inv
	}
}

// OpenAIEmbeddingProvider 调用 OpenAI 兼容 Embeddings API（可选）。
type OpenAIEmbeddingProvider struct {
	apiKey  string
	model   string
	dim     int
	baseURL string
	client  *http.Client
}

func (o *OpenAIEmbeddingProvider) Dimensions() int {
	if o.dim <= 0 {
		return 1536
	}
	return o.dim
}

func (o *OpenAIEmbeddingProvider) Name() string { return "openai:" + o.model }

func (o *OpenAIEmbeddingProvider) Embed(ctx context.Context, texts []string) ([][]float32, error) {
	if len(texts) == 0 {
		return nil, nil
	}
	base := o.baseURL
	if base == "" {
		base = "https://api.openai.com"
	}
	body, _ := json.Marshal(map[string]any{
		"model": o.model,
		"input": texts,
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+"/v1/embeddings", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+o.apiKey)
	resp, err := o.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		slurp, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("embeddings API %d: %s", resp.StatusCode, string(slurp))
	}
	var parsed struct {
		Data []struct {
			Embedding []float32 `json:"embedding"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return nil, err
	}
	out := make([][]float32, len(parsed.Data))
	for i, row := range parsed.Data {
		out[i] = row.Embedding
	}
	return out, nil
}

// EncodeFloat32Slice 将向量序列化为 SQLite BLOB。
func EncodeFloat32Slice(v []float32) []byte {
	buf := make([]byte, 4*len(v))
	for i, x := range v {
		binary.LittleEndian.PutUint32(buf[i*4:], math.Float32bits(x))
	}
	return buf
}

// DecodeFloat32Slice 从 BLOB 反序列化向量。
func DecodeFloat32Slice(blob []byte, dim int) []float32 {
	if dim <= 0 || len(blob) < 4*dim {
		return nil
	}
	out := make([]float32, dim)
	for i := 0; i < dim; i++ {
		out[i] = math.Float32frombits(binary.LittleEndian.Uint32(blob[i*4:]))
	}
	return out
}

// CosineSimilarity 假设向量已归一化；未归一化时仍可用。
func CosineSimilarity(a, b []float32) float64 {
	if len(a) == 0 || len(a) != len(b) {
		return 0
	}
	var dot, na, nb float64
	for i := range a {
		dot += float64(a[i]) * float64(b[i])
		na += float64(a[i]) * float64(a[i])
		nb += float64(b[i]) * float64(b[i])
	}
	if na == 0 || nb == 0 {
		return 0
	}
	return dot / (math.Sqrt(na) * math.Sqrt(nb))
}
