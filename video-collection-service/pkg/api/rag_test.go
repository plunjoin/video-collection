package api

import (
	"encoding/json"
	"fmt"
	"testing"

	"video-collection-service/pkg/rag"
)

func TestAdminRAGRebuildAndSearch(t *testing.T) {
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
