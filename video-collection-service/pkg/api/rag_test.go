package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"video-collection-service/pkg/rag"
	"video-collection-service/pkg/store"
)

func TestAdminRAGRebuildAndSearch(t *testing.T) {
	t.Setenv("RAG_EMBEDDING_PROVIDER", "fake")
	f := newContentFixture(t)
	subjectJSON := `{"name":"RAG API词条","type":"work","sub_type":"tokusatsu","summary":"管理员检索测试用摘要内容。"}`
	res := f.request("POST", "/api/admin/wiki/subjects", subjectJSON, f.admin, 200)
	var subjectID int
	if err := json.Unmarshal(res["id"], &subjectID); err != nil || subjectID <= 0 {
		t.Fatalf("bad subject id: %v", err)
	}

	f.request("POST", "/api/admin/rag/rebuild", `{}`, f.alice, 401)
	rebuildRes := f.request("POST", "/api/admin/rag/rebuild", `{}`, f.admin, 200)
	var chunksIndexed int
	if err := json.Unmarshal(rebuildRes["chunks_indexed"], &chunksIndexed); err != nil || chunksIndexed <= 0 {
		t.Fatalf("expected chunks_indexed > 0, got %v err=%v", rebuildRes["chunks_indexed"], err)
	}

	searchRes := f.request("GET", fmt.Sprintf("/api/admin/rag/search?q=%s&top_k=3", "特摄"), "", f.admin, 200)
	data := decodeContentData[rag.SearchResponse](t, searchRes)
	if len(data.Results) == 0 {
		t.Fatalf("expected search results, got %+v", data)
	}
}

func TestAdminRAGAsk(t *testing.T) {
	chat := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"choices":[{"message":{"content":"本地问答答案。[1]"}}]}`)
	}))
	defer chat.Close()
	t.Setenv("RAG_EMBEDDING_PROVIDER", "fake")
	t.Setenv("OPENAI_BASE_URL", chat.URL)
	t.Setenv("OPENAI_API_KEY", "test-key")
	f := newContentFixture(t)
	f.request("POST", "/api/admin/rag/ask", `{"q":"测试"}`, nil, 401)
	f.request("POST", "/api/admin/rag/ask", `{"q":"测试"}`, f.alice, 401)
	f.request("POST", "/api/admin/rag/ask", `{"q":"  "}`, f.admin, 400)
	f.request("POST", "/api/admin/rag/ask", `{`, f.admin, 400)
	f.request("GET", "/api/admin/rag/ask", "", f.admin, 405)
	_, err := f.s.CreateWikiSubject(context.Background(), &store.WikiSubject{
		Name: "问答测试", Type: "work", SubType: "anime", Summary: "本地资料。",
	})
	if err != nil {
		t.Fatal(err)
	}
	f.request("POST", "/api/admin/rag/rebuild", `{}`, f.admin, 200)
	for _, field := range []string{"q", "query"} {
		res := f.request("POST", "/api/admin/rag/ask", fmt.Sprintf(`{"%s":"测试","top_k":1}`, field), f.admin, 200)
		data := decodeContentData[rag.AskResponse](t, res)
		if data.Answer != "本地问答答案。[1]" || len(data.Citations) != 1 {
			t.Fatalf("unexpected ask response: %+v", data)
		}
	}
	chat.Close()
	f.request("POST", "/api/admin/rag/ask", `{"q":"测试"}`, f.admin, 502)
	w := httptest.NewRecorder()
	(&Server{}).handleAdminRAGAsk(w, httptest.NewRequest("POST", "/api/admin/rag/ask", nil))
	if w.Code != 503 {
		t.Fatalf("disabled RAG returned %d", w.Code)
	}
}
