package rag

import (
	"context"
	"path/filepath"
	"testing"

	"video-collection-service/pkg/store"
)

func TestRAGRebuildAndSearch(t *testing.T) {
	ctx := context.Background()
	dbPath := filepath.Join(t.TempDir(), "rag.db")
	s, err := store.NewSQLiteStore(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })

	svc := NewService(s, s, &FakeEmbeddingProvider{dim: 32})
	id, err := s.CreateWikiSubject(ctx, &store.WikiSubject{
		Name:    "RAG测试词条",
		Type:    "work",
		SubType: "anime",
		Summary: "用于向量检索验证的特摄知识摘要。",
	})
	if err != nil {
		t.Fatal(err)
	}
	n, err := svc.IndexWikiSubject(ctx, id)
	if err != nil || n == 0 {
		t.Fatalf("index subject: n=%d err=%v", n, err)
	}
	res, err := svc.Search(ctx, "特摄知识", 5, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Results) == 0 {
		t.Fatal("expected search hits")
	}
	if res.Results[0].Similarity <= 0 {
		t.Fatalf("expected positive similarity, got %f", res.Results[0].Similarity)
	}
}
