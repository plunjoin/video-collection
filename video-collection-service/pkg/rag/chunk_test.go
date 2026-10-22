package rag

import (
	"strings"
	"testing"

	"video-collection-service/pkg/store"
)

func TestSplitTextOverlap(t *testing.T) {
	var b strings.Builder
	for i := 0; i < 1200; i++ {
		b.WriteRune('测')
	}
	parts := splitText(b.String(), 400, 50)
	if len(parts) < 2 {
		t.Fatalf("expected multiple chunks, got %d", len(parts))
	}
}

func TestBuildWikiSubjectChunks(t *testing.T) {
	d := &store.WikiSubjectDetail{
		WikiSubject: store.WikiSubject{
			ID:      1,
			Name:    "测试作品",
			Type:    "work",
			SubType: "anime",
			Summary: "这是一段足够长的摘要，用于验证分块逻辑能够产出可检索文本。",
			Infobox: map[string]any{"年份": 2024},
			Aliases: []string{"Test Anime"},
		},
	}
	chunks := BuildWikiSubjectChunks(d)
	if len(chunks) == 0 {
		t.Fatal("expected chunks")
	}
	if chunks[0].SourceType != SourceWikiSubject || chunks[0].SubjectID != 1 {
		t.Fatalf("unexpected first chunk: %+v", chunks[0])
	}
}
