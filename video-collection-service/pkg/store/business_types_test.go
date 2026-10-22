package store

import (
	"context"
	"path/filepath"
	"reflect"
	"testing"

	"video-collection-service/config"
)

func TestValidateBusinessValuesEnum(t *testing.T) {
	b := &BusinessType{Fields: []BusinessTypeField{{Name: "status", DataType: "enum", Required: true, Options: []string{"draft", "live"}}}}
	for _, tc := range []struct {
		value string
		valid bool
	}{
		{"draft", true}, {"live", true}, {"", false}, {"LIVE", false}, {"other", false},
	} {
		t.Run(tc.value, func(t *testing.T) {
			values, err := ValidateBusinessValues(b, map[string]string{"status": tc.value})
			if tc.valid {
				if err != nil || len(values) != 1 || values[0] != tc.value {
					t.Fatalf("enum value: %v, %v", values, err)
				}
			} else if err == nil {
				t.Fatalf("accepted invalid enum %q", tc.value)
			}
		})
	}
}

func TestBusinessRowSystemTimeFilters(t *testing.T) {
	// System time bounds work without schema fields, and even SQL-like input
	// remains a string argument rather than becoming part of the query.
	const min = "2026-01-01T00:00:00Z' OR 1=1 --"
	where, args, err := businessRowFilters(&BusinessType{}, map[string]string{
		"created_at_min": min, "created_at_max": "2026-12-31",
		"updated_at_min": "2026-02-01", "updated_at_max": "2026-11-30",
	})
	want := ` WHERE "created_at"<=$1 AND "created_at">=$2 AND "updated_at"<=$3 AND "updated_at">=$4`
	if err != nil || where != want || !reflect.DeepEqual(args, []any{"2026-12-31", min, "2026-11-30", "2026-02-01"}) {
		t.Fatalf("time filters: %q, %v, %v", where, args, err)
	}
}

func TestBusinessTypesRegistryAndSchema(t *testing.T) {
	ctx := context.Background()
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "biz.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	types, err := s.ListBusinessTypes(ctx)
	if err != nil || len(types) != 3 {
		t.Fatalf("seed: %+v %v", types, err)
	}
	for _, b := range types {
		if !b.IsSystem || len(b.Fields) == 0 {
			t.Fatalf("missing system metadata: %+v", b)
		}
		for _, f := range b.Fields {
			if !f.IsSystem {
				t.Fatal("seed field not system")
			}
		}
	}
	if err = s.DeleteBusinessType(ctx, "article"); err == nil {
		t.Fatal("deleted system type")
	}
	if err = s.DeleteBusinessTypeField(ctx, "article", "title"); err == nil {
		t.Fatal("deleted system field")
	}
	for _, f := range []BusinessTypeField{{Name: "renamed", Required: true}, {DataType: "integer", Required: true}, {Required: false}} {
		if err = s.UpdateBusinessTypeField(ctx, "article", "title", f); err == nil {
			t.Fatalf("changed core semantics: %+v", f)
		}
	}
	if err = s.AddBusinessTypeField(ctx, "article", BusinessTypeField{Name: "extra", DataType: "json"}); err != nil {
		t.Fatal(err)
	}
	b := BusinessType{Slug: "demo_item", Name: "演示", Fields: []BusinessTypeField{{Name: "title", Required: true}, {Name: "score", DataType: "integer"}}}
	if err = s.CreateBusinessType(ctx, b); err != nil {
		t.Fatal(err)
	}
	if err = s.AddBusinessTypeField(ctx, b.Slug, BusinessTypeField{Name: "enabled", DataType: "boolean"}); err != nil {
		t.Fatal(err)
	}
	rows, err := s.db.Query(`PRAGMA table_info(biz_demo_item)`)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for rows.Next() {
		var cid, notnull, pk int
		var name, typ string
		var def any
		if err = rows.Scan(&cid, &name, &typ, &notnull, &def, &pk); err != nil {
			t.Fatal(err)
		}
		if name == "enabled" {
			found = true
		}
	}
	rows.Close()
	if !found {
		t.Fatal("ADD COLUMN missing")
	}
	r := CollectionRecord{SourceID: "test", Target: b.Slug, Key: "1", Values: map[string]string{"title": "First", "score": "7", "enabled": "true"}}
	if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || !saved {
		t.Fatalf("save: %v %v", saved, err)
	}
	var title, payload string
	var score, id int
	var enabled bool
	if err = s.db.QueryRow(`SELECT id,title,score,enabled,payload FROM biz_demo_item`).Scan(&id, &title, &score, &enabled, &payload); err != nil || score != 7 || !enabled {
		t.Fatalf("row: %s %d %v %v", title, score, enabled, err)
	}
	records, total, err := s.ListCollectionRecords(ctx, "test", 1, 10)
	if err != nil || total != 1 || records[0].Target != b.Slug || records[0].ContentID != id {
		t.Fatalf("audit: %+v %v", records, err)
	}
	r.Values["score"] = "9"
	if saved, err := s.SaveCollectionRecord(ctx, r, true); err != nil || saved {
		t.Fatalf("skip: %v %v", saved, err)
	}
	if _, err = s.SaveCollectionRecord(ctx, r, false); err != nil {
		t.Fatal(err)
	}
	var count int
	s.db.QueryRow(`SELECT COUNT(*),score FROM biz_demo_item`).Scan(&count, &score)
	if count != 1 || score != 9 {
		t.Fatalf("upsert count=%d score=%d", count, score)
	}
	r.SourceID = "second"
	if _, err = s.SaveCollectionRecord(ctx, r, false); err != nil {
		t.Fatal(err)
	}
	s.db.QueryRow(`SELECT COUNT(*) FROM biz_demo_item`).Scan(&count)
	if count != 2 {
		t.Fatal("source keys collided")
	}
	for _, v := range []map[string]string{{"score": "2"}, {"title": "bad", "score": "not integer"}, {"title": "bad", "enabled": "not boolean"}} {
		r.Values = v
		if _, err = s.SaveCollectionRecord(ctx, r, false); err == nil {
			t.Fatalf("invalid row accepted: %+v", v)
		}
	}
	if err = s.DeleteBusinessType(ctx, b.Slug); err == nil {
		t.Fatal("deleted used type")
	}
	if err = s.DeleteBusinessTypeField(ctx, b.Slug, "enabled"); err != nil {
		t.Fatal(err)
	}
	if _, err = s.db.Exec(`SELECT enabled FROM biz_demo_item`); err == nil {
		t.Fatal("column not dropped")
	}
	// Edits and deletes must update the physical row, even if rectification has
	// repointed the audit content_id to a Wiki/video entity.
	if err = s.UpdateCollectionRecord(ctx, "test", b.Slug, "1", map[string]string{"title": "Edited", "score": "12"}); err != nil {
		t.Fatal(err)
	}
	if err = s.db.QueryRow(`SELECT score FROM biz_demo_item WHERE source_id='test'`).Scan(&score); err != nil || score != 12 {
		t.Fatalf("edit: %d %v", score, err)
	}
	if _, err = s.db.Exec(`UPDATE collection_records SET content_id=999 WHERE source_id='test'`); err != nil {
		t.Fatal(err)
	}
	if err = s.DeleteCollectionRecord(ctx, "test", b.Slug, "1"); err != nil {
		t.Fatal(err)
	}
	if err = s.db.QueryRow(`SELECT COUNT(*) FROM biz_demo_item`).Scan(&count); err != nil || count != 1 {
		t.Fatalf("delete: %d %v", count, err)
	}
	if err = s.DeleteCollectionRecord(ctx, "second", b.Slug, "1"); err != nil {
		t.Fatal(err)
	}
	if err = s.DeleteBusinessType(ctx, b.Slug); err != nil {
		t.Fatal(err)
	}

}

func TestBusinessTypeControlledDDLAndDeletion(t *testing.T) {
	ctx := context.Background()
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "biz.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	for _, slug := range []string{"article", "video", "record", "biz_bad", "UPPER", "x", "evil\"; DROP TABLE users;--"} {
		if err = s.CreateBusinessType(ctx, BusinessType{Slug: slug, Name: "bad"}); err == nil {
			t.Fatal("accepted slug", slug)
		}
	}
	for _, name := range []string{"id", "payload", "record_key", "source_id", "created_at", "updated_at", "Bad", "x\""} {
		if err = s.CreateBusinessType(ctx, BusinessType{Slug: "bad_item", Name: "bad", Fields: []BusinessTypeField{{Name: name}}}); err == nil {
			t.Fatal("accepted column", name)
		}
	}
	if err = s.CreateBusinessType(ctx, BusinessType{Slug: "empty_item", Name: "Empty", TableName: "users", Writer: "article", IsSystem: true}); err != nil {
		t.Fatal(err)
	}
	b, err := s.GetBusinessType(ctx, "empty_item")
	if err != nil || b.Writer != "table" || b.TableName != "biz_empty_item" || b.IsSystem {
		t.Fatalf("trusted client routing: %+v %v", b, err)
	}
	src := config.SourceConfig{ID: "bind", Name: "Bound", Filter: config.FilterRule{Pipeline: &config.PipelineRule{Target: b.Slug}}}
	if err = s.SaveSource(ctx, src); err != nil {
		t.Fatal(err)
	}
	if err = s.DeleteBusinessType(ctx, b.Slug); err == nil {
		t.Fatal("deleted bound type")
	}
	if err = s.DeleteSource(ctx, src.ID); err != nil {
		t.Fatal(err)
	}
	if err = s.DeleteBusinessType(ctx, b.Slug); err != nil {
		t.Fatal(err)
	}
	if _, err = s.db.Exec(`SELECT * FROM biz_empty_item`); err == nil {
		t.Fatal("table survived")
	}
	// Reopening runs the seed migration again and preserves custom system fields.
	if err = s.SQLContentStore.initSchema(false); err != nil {
		t.Fatal(err)
	}
}

func TestBusinessRowRollsBackWithAudit(t *testing.T) {
	ctx := context.Background()
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "atomic.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if err = s.CreateBusinessType(ctx, BusinessType{Slug: "atomic_item", Name: "Atomic"}); err != nil {
		t.Fatal(err)
	}
	if _, err = s.db.Exec(`CREATE TRIGGER reject_audit BEFORE INSERT ON collection_records BEGIN SELECT RAISE(ABORT,'audit rejected'); END`); err != nil {
		t.Fatal(err)
	}
	if _, err = s.SaveCollectionRecord(ctx, CollectionRecord{SourceID: "test", Target: "atomic_item", Key: "1", Values: map[string]string{"x": "value"}}, false); err == nil {
		t.Fatal("expected audit failure")
	}
	var n int
	if err = s.db.QueryRow(`SELECT COUNT(*) FROM biz_atomic_item`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("orphan row: %d %v", n, err)
	}
}
