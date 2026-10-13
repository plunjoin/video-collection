package api

import (
	"testing"
)

func TestCleanSeriesRoot(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"斗罗大陆 第2季", "斗罗大陆"},
		{"斗罗大陆2 绝世唐门", "斗罗大陆"},
		{"进击的巨人 最终季 Part.2", "进击的巨人"},
		{"鬼灭之刃：柱训练篇", "鬼灭之刃"},
		{"凡人修仙传 重置版", "凡人修仙传"},
		{"海贼王", "海贼王"},
		{"刀剑神域 Alicization", "刀剑神域"},
		{"一人之下 第5季", "一人之下"},
		{"名侦探柯南剧场版：百万美元的五棱星", "名侦探柯南"},
		{"【普通话】完美世界 剧场版", "完美世界"},
	}

	for _, tt := range tests {
		got := cleanSeriesRoot(tt.input)
		if got != tt.expected {
			t.Errorf("cleanSeriesRoot(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}

func TestExtractSeriesKeywords(t *testing.T) {
	kws := extractSeriesKeywords("斗罗大陆 第2季", "斗罗大陆第二季")
	if len(kws) == 0 {
		t.Fatalf("expected non-empty keywords")
	}
	if kws[0] != "斗罗大陆" {
		t.Errorf("expected first keyword to be '斗罗大陆', got %q", kws[0])
	}
	t.Logf("extracted keywords: %v", kws)
}
