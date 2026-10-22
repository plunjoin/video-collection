package store

import (
	"bytes"
	"context"
	"path/filepath"
	"testing"
)

func TestSQLiteWebhookAndRAGMigrations(t *testing.T) {
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "migrations.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	exerciseWebhookAndRAGMigrations(t, s.SQLContentStore, false)
}

// Run against both engines, including PostgreSQL's transaction-abort behavior.
func exerciseWebhookAndRAGMigrations(t *testing.T, s *SQLContentStore, postgres bool) {
	t.Helper()
	ctx := context.Background()
	wh := &Webhook{
		ID: "migration-test", Name: "preserved", SecretHint: "hint",
		Events: []string{"created"}, ToleranceSec: 123, Enabled: true,
	}
	if err := s.CreateWebhook(ctx, wh, "test-cipher"); err != nil {
		t.Fatal(err)
	}
	embedding := []byte{0, 1, 127, 128, 255}
	if err := s.ReplaceRAGChunks(ctx, "test", "migration", []RAGChunkRow{{
		SourceType: "test", SourceID: "migration", Text: "preserved",
		Embedding: embedding, Dimensions: 1,
	}}); err != nil {
		t.Fatal(err)
	}
	// Existing columns must neither abort initialization nor lose custom values.
	if err := s.initSchema(postgres); err != nil {
		t.Fatalf("repeat initialization: %v", err)
	}
	got, err := s.GetWebhook(ctx, wh.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got == nil || got.ToleranceSec != 123 || got.SecretHint != "hint" || len(got.Events) != 1 || got.Events[0] != "created" {
		t.Fatalf("repeat initialization changed webhook: %+v", got)
	}
	// Reconstruct the legacy schema while retaining its existing webhook row.
	for _, column := range []string{"tolerance_sec", "events", "secret_hint"} {
		if _, err := s.db.Exec("ALTER TABLE webhooks DROP COLUMN " + column); err != nil {
			t.Fatal(err)
		}
	}
	for i := 0; i < 2; i++ {
		if err := s.initSchema(postgres); err != nil {
			t.Fatalf("legacy upgrade/restart %d: %v", i, err)
		}
	}
	got, err = s.GetWebhook(ctx, wh.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got == nil || got.Name != wh.Name || got.ToleranceSec != 300 || got.SecretHint != "" || len(got.Events) != 0 {
		t.Fatalf("legacy upgrade lost row or defaults: %+v", got)
	}
	chunks, err := s.ListRAGChunksForSearch(ctx, "test")
	if err != nil {
		t.Fatal(err)
	}
	if len(chunks) != 1 || !bytes.Equal(chunks[0].Embedding, embedding) {
		t.Fatalf("binary embedding lost during migration: %+v", chunks)
	}
}
