package rag

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"video-collection-service/pkg/store"
)

type askWikiReader struct {
	WikiReader
	roots []int
	fail  bool
}

func (w *askWikiReader) GetWikiGraph(ctx context.Context, rootID, depth int) (*store.WikiGraphData, error) {
	w.roots = append(w.roots, rootID)
	if depth != 1 {
		return nil, fmt.Errorf("unexpected depth %d", depth)
	}
	if w.fail {
		return nil, errors.New("graph unavailable")
	}
	return &store.WikiGraphData{
		Nodes: []store.WikiGraphNode{{ID: rootID, Name: "测试作品"}, {ID: 100, Name: "测试导演"}},
		Edges: []store.WikiGraphEdge{{Source: rootID, Target: 100, Relation: "director", Role: "导演"}},
	}, nil
}

func TestAskWithCitationsAndGraph(t *testing.T) {
	var userPrompt string
	chat := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "Bearer test-key" {
			t.Errorf("unexpected chat request: %s %s", r.Method, r.URL.Path)
		}
		var body struct {
			Model     string                           `json:"model"`
			MaxTokens int                              `json:"max_tokens"`
			Messages  []struct{ Role, Content string } `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if body.Model != "test-chat" || body.MaxTokens != 256 || len(body.Messages) != 2 {
			t.Errorf("unexpected chat body: %+v", body)
		} else {
			if body.Messages[0].Role != "system" || !strings.Contains(body.Messages[0].Content, "禁止使用外部知识") {
				t.Error("missing grounding system prompt")
			}
			userPrompt = body.Messages[1].Content
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"choices":[{"message":{"content":"这是资料中的答案。[1]"}}]}`)
	}))
	defer chat.Close()
	t.Setenv("OPENAI_BASE_URL", chat.URL)
	t.Setenv("OPENAI_API_KEY", "test-key")
	t.Setenv("RAG_CHAT_MODEL", "test-chat")
	t.Setenv("RAG_CHAT_MAX_TOKENS", "256")
	t.Setenv("RAG_CHAT_SYSTEM_PROMPT", "")
	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "ask.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.SetRAGContentIngestHook(nil); _ = s.Close() })
	wiki := &askWikiReader{WikiReader: s}
	svc := NewService(s, wiki, &FakeEmbeddingProvider{dim: 32})
	ctx := context.Background()
	for i := 0; i < 4; i++ {
		id, err := s.CreateWikiSubject(ctx, &store.WikiSubject{
			Name: fmt.Sprintf("测试作品%d", i), Type: "work", SubType: "anime",
			Summary: "测试摘要资料", Aliases: []string{"别名"},
		})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := svc.IndexWikiSubject(ctx, id); err != nil {
			t.Fatal(err)
		}
	}
	result, err := svc.Ask(ctx, " 测试作品 ", 50, SourceWikiSubject)
	if err != nil {
		t.Fatal(err)
	}
	if result.Answer != "这是资料中的答案。[1]" || result.Model != "test-chat" || result.Embedder != "fake" || result.Query != "测试作品" || result.TopK != 50 {
		t.Fatalf("unexpected response: %+v", result)
	}
	if len(result.Citations) != 8 || len(wiki.roots) != 3 || result.GraphNote == "" {
		t.Fatalf("expected 8 chunks and 3 distinct graph roots: %+v, roots=%v", result, wiki.roots)
	}
	seen := map[int]bool{}
	for _, root := range wiki.roots {
		if seen[root] {
			t.Fatal("graph root queried twice")
		}
		seen[root] = true
	}
	for i, citation := range result.Citations {
		if !strings.Contains(userPrompt, fmt.Sprintf("[%d] 来源=%s，source_id=%s", i+1, citation.SourceType, citation.SourceID)) || !strings.Contains(userPrompt, citation.Text) {
			t.Fatal("citation does not match the supplied context")
		}
	}
	if !strings.Contains(userPrompt, "测试导演") || !strings.Contains(userPrompt, "[图谱:") {
		t.Fatal("missing graph evidence in prompt")
	}

	wiki.fail = true
	result, err = svc.Ask(ctx, "测试", 1, SourceWikiSubject)
	if err != nil || result.GraphNote != "" || len(result.Citations) != 1 {
		t.Fatalf("graph failure should preserve chunk Q&A: %+v %v", result, err)
	}
	result, err = svc.Ask(ctx, "不存在", 5, SourceNews)
	if err != nil || len(result.Citations) != 0 || !strings.Contains(userPrompt, "资料不足") {
		t.Fatalf("empty filtered search: %+v %v", result, err)
	}
	if _, err := svc.Ask(ctx, "  ", 5, ""); err == nil {
		t.Fatal("empty query must fail")
	}
}

func TestAskChatErrorsAndConfiguration(t *testing.T) {
	for _, tc := range []struct {
		name   string
		status int
		body   string
		want   string
	}{
		{"upstream", 429, `{"error":"rate limited test-key"}`, "HTTP 429"},
		{"malformed", 200, `invalid`, "解析响应"},
		{"no choices", 200, `{"choices":[]}`, "空答案"},
		{"empty answer", 200, `{"choices":[{"message":{"content":" "}}]}`, "空答案"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/v1/chat/completions" {
					t.Errorf("duplicated /v1: %s", r.URL.Path)
				}
				w.WriteHeader(tc.status)
				fmt.Fprint(w, tc.body)
			}))
			defer server.Close()
			t.Setenv("OPENAI_BASE_URL", server.URL+"/v1/")
			t.Setenv("OPENAI_API_KEY", "test-key")
			_, err := NewChatClientFromEnv().Complete(context.Background(), "问题")
			if !errors.Is(err, ErrChat) || !strings.Contains(err.Error(), tc.want) || strings.Contains(err.Error(), "test-key") {
				t.Fatalf("unexpected chat error: %v", err)
			}
		})
	}
	t.Setenv("OPENAI_API_KEY", "")
	t.Setenv("RAG_CHAT_MODEL", "")
	t.Setenv("RAG_CHAT_MAX_TOKENS", "")
	t.Setenv("RAG_CHAT_TIMEOUT_SEC", "")
	t.Setenv("RAG_CHAT_SYSTEM_PROMPT", "自定义系统提示")
	client := NewChatClientFromEnv()
	if client.model != "gemini-3.6-flash" || client.client.Timeout != 60*time.Second || client.maxTokens != 0 || client.systemPrompt != "自定义系统提示" {
		t.Fatalf("unexpected configuration: model=%s timeout=%s", client.model, client.client.Timeout)
	}
	if _, err := client.Complete(context.Background(), "问题"); !errors.Is(err, ErrChat) || !strings.Contains(err.Error(), "OPENAI_API_KEY") {
		t.Fatalf("missing key should fail clearly: %v", err)
	}
}
