package rag

import (
	"context"
	"testing"
)

func TestFakeEmbeddingDeterministic(t *testing.T) {
	p := &FakeEmbeddingProvider{dim: 64}
	a, err := p.Embed(context.Background(), []string{"hello"})
	if err != nil || len(a) != 1 || len(a[0]) != 64 {
		t.Fatalf("embed failed: %v len=%d", err, len(a[0]))
	}
	b, _ := p.Embed(context.Background(), []string{"hello"})
	if a[0][0] != b[0][0] {
		t.Fatal("expected deterministic embedding")
	}
}

func TestCosineSimilarity(t *testing.T) {
	v := []float32{1, 0, 0}
	sim := CosineSimilarity(v, v)
	if sim < 0.99 {
		t.Fatalf("expected ~1, got %f", sim)
	}
}
