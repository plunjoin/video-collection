package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadPreservesExplicitZeroLimits(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(path, []byte("sources:\n  - id: full\n    collect_hours: 0\n    retry_count: 0\n  - id: default\n"), 0600); err != nil {
		t.Fatal(err)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Sources[0].CollectHours != 0 || cfg.Sources[0].RetryCount != 0 || cfg.Sources[1].CollectHours != 24 {
		t.Fatalf("incorrect defaults: %+v", cfg.Sources)
	}
}

func TestCustomAliasKeepsTemplateMapping(t *testing.T) {
	path := filepath.Join(t.TempDir(), "templates.yaml")
	t.Setenv("COLLECTION_TEMPLATES_PATH", path)
	if err := os.WriteFile(path, []byte("- id: custom\n  name: 自定义\n  aliases: [my_format]\n  rule:\n    version: 1\n    format: custom_json\n    method: GET\n    mapping: {list_path: results, name_path: metadata.title}\n"), 0600); err != nil {
		t.Fatal(err)
	}
	rule, err := ResolveCollectionRule(SourceConfig{Type: "my_format"})
	if err != nil || rule.Mapping.ListPath != "results" || rule.Mapping.NamePath != "metadata.title" {
		t.Fatalf("template mapping overwritten: %+v %v", rule, err)
	}
}
