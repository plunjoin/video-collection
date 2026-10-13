package maccms

import (
	"testing"
)

func TestParsePlayGroups(t *testing.T) {
	playFrom := "m3u8$$$qq"
	playServer := "no$$$no"
	playNote := "$$$"
	playURL := "第01集$https://example.com/1.m3u8#第02集$https://example.com/2.m3u8$$$第01集$https://v.qq.com/1#第02集$https://v.qq.com/2"

	groups := ParsePlayGroups(playFrom, playServer, playNote, playURL)
	if len(groups) != 2 {
		t.Fatalf("expected 2 groups, got %d", len(groups))
	}

	// 验证第一个分组 (m3u8)
	if groups[0].PlayerCode != "m3u8" {
		t.Errorf("expected player code m3u8, got %s", groups[0].PlayerCode)
	}
	if len(groups[0].Episodes) != 2 {
		t.Fatalf("expected 2 episodes in group 0, got %d", len(groups[0].Episodes))
	}
	if groups[0].Episodes[0].Name != "第01集" || groups[0].Episodes[0].URL != "https://example.com/1.m3u8" {
		t.Errorf("unexpected episode 0: %+v", groups[0].Episodes[0])
	}
	if groups[0].Episodes[1].Name != "第02集" || groups[0].Episodes[1].URL != "https://example.com/2.m3u8" {
		t.Errorf("unexpected episode 1: %+v", groups[0].Episodes[1])
	}

	// 验证第二个分组 (qq)
	if groups[1].PlayerCode != "qq" {
		t.Errorf("expected player code qq, got %s", groups[1].PlayerCode)
	}
	if len(groups[1].Episodes) != 2 {
		t.Fatalf("expected 2 episodes in group 1, got %d", len(groups[1].Episodes))
	}
}

func TestParseSinglePlayGroupWithoutDollar(t *testing.T) {
	playFrom := "m3u8"
	playServer := "no"
	playNote := ""
	playURL := "https://example.com/single.m3u8"

	groups := ParsePlayGroups(playFrom, playServer, playNote, playURL)
	if len(groups) != 1 {
		t.Fatalf("expected 1 group, got %d", len(groups))
	}
	if len(groups[0].Episodes) != 1 {
		t.Fatalf("expected 1 episode, got %d", len(groups[0].Episodes))
	}
	if groups[0].Episodes[0].Name != "第01集" {
		t.Errorf("expected default episode name 第01集, got %s", groups[0].Episodes[0].Name)
	}
	if groups[0].Episodes[0].URL != "https://example.com/single.m3u8" {
		t.Errorf("expected url https://example.com/single.m3u8, got %s", groups[0].Episodes[0].URL)
	}
}
