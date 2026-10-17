package ingest

import (
	"context"
	"fmt"
	"testing"

	"video-collection-service/config"
	"video-collection-service/pkg/store"
)

func TestLiveAGIHuntIngestionAndDBPersistence(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping live test in short mode")
	}

	st, err := store.NewSQLiteStore("../../data/collection.db")
	if err != nil {
		t.Fatalf("failed to open database: %v", err)
	}
	defer st.Close()

	ctx := context.Background()
	src := config.SourceConfig{
		ID:           "agihunt_ai_news",
		Name:         "AGI Hunt · AI 实时快讯 / 日报",
		Type:         "pipeline",
		API:          "https://agihunt.info/feed.xml",
		Enabled:      true,
		PageLimit:    1,
		TimeoutSec:   15,
		RetryCount:   2,
		IntervalMs:   300,
		Headers:      map[string]string{"User-Agent": "Mozilla/5.0 (compatible; BlliiFamiliar/1.0; +https://bllii.fun)"},
		CustomParams: map[string]string{},
		Filter: config.FilterRule{
			Pipeline: &config.PipelineRule{
				Version:    1,
				Input:      "rss",
				Target:     "article",
				KeyField:   "link",
				Duplicate:  "skip",
				MaxRecords: 30,
				Fields: []config.FieldRule{
					{Target: "title", Selector: "title", Required: true, Trim: true, StripHTML: true},
					{Target: "content", Selector: "description", Required: true, Trim: true},
					{Target: "summary", Selector: "summary", Trim: true, StripHTML: true},
					{Target: "link", Selector: "link", Required: true, Trim: true},
					{Target: "category", Selector: "category", Default: "AI快讯"},
					{Target: "author", Selector: "creator", Default: "AGI Hunt"},
					{Target: "cover", Selector: "cover"},
				},
			},
		},
	}

	if err := st.SaveSource(ctx, src); err != nil {
		t.Fatalf("failed to save source: %v", err)
	}

	fetched := 0
	saved := 0
	skipped := 0

	err = Run(ctx, src, 30, func(s Sample) error {
		fetched++
		if len(s.Errors) > 0 {
			skipped++
			return nil
		}
		v := s.Values
		r := store.CollectionRecord{
			SourceID: src.ID,
			Target:   "article",
			Key:      v["link"],
			Values:   v,
		}
		isSaved, err := st.SaveCollectionRecord(ctx, r, true)
		if err != nil {
			return err
		}
		if isSaved {
			saved++
		} else {
			skipped++
		}
		return nil
	})

	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	fmt.Printf("\n====== AGI Hunt 采集成果 ======\n")
	fmt.Printf("总计读取: %d 条\n", fetched)
	fmt.Printf("成功入库: %d 条\n", saved)
	fmt.Printf("跳过重复: %d 条\n", skipped)

	news, total, err := st.ListContent(ctx, store.ContentQuery{Kind: "news", Page: 1, PageSize: 5, Admin: true})
	if err != nil {
		t.Fatalf("ListContent failed: %v", err)
	}
	fmt.Printf("资讯库最新条目 (总共 %d 篇):\n", total)
	for i, n := range news {
		fmt.Printf("[%d] ID=%d 标题: %s (分类: %s, 状态: %s, 作者: %s)\n", i+1, n.ID, n.Title, n.Category, n.Status, n.AuthorName)
		fmt.Printf("    摘要: %s\n", n.Summary)
	}
}
