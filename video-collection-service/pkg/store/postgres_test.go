package store

import (
	"context"
	"testing"
)

func TestPostgresConnection(t *testing.T) {
	dsn := "postgres://postgres:postgres@localhost:5432/videodb?sslmode=disable"
	store, err := NewPostgresStore(dsn)
	if err != nil {
		t.Skipf("Skipping PostgreSQL integration test: %v", err)
		return
	}
	defer store.db.Close()

	ctx := context.Background()
	cats, err := store.GetCategories(ctx)
	if err != nil {
		t.Fatalf("Failed to get categories: %v", err)
	}
	t.Logf("Successfully connected! Found %d categories", len(cats))
}
