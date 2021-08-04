package maccms

import (
	"testing"

	"video-collection-api/config"
)

func TestFilterEngine(t *testing.T) {
	cfg := config.SourceConfig{
		ID:   "test_source",
		Name: "测试源",
		CategoryMappings: []config.CategoryMapping{
			{
				SourceTypeID:   1,
				SourceTypeName: "电影",
				TargetTypeID:   100,
				TargetTypeName: "大电影",
			},
		},
		Filter: config.FilterRule{
			IgnoreNameKeywords: []string{"预告片"},
			NameCleanPrefixes:  []string{"【高清】"},
			AllowedPlayers:     []string{"m3u8"},
			PlayerMappings: map[string]string{
				"kkm3u8": "m3u8",
			},
			RequirePlayURLs: true,
			ContentReplacePatterns: []config.ReplaceRule{
				{
					Pattern:     "广告：.*",
					IsRegex:     true,
					Replacement: "",
				},
			},
		},
	}

	fe := NewFilterEngine(cfg)

	// 测试用例 1: 正常条目并测试前缀清除、分类映射、播放源别名映射与广告清洗
	vod1 := VodItem{
		VodID:       FlexInt(1001),
		VodName:     "【高清】肖申克的救赎",
		TypeID:      FlexInt(1),
		TypeName:    "电影",
		VodPlayFrom: "kkm3u8",
		VodPlayURL:  "正片$https://test.com/shawshank.m3u8",
		VodContent:  "这是一部伟大的电影。广告：联系QQ123456",
	}

	cleaned, ok := fe.CleanAndTransform(vod1)
	if !ok || cleaned == nil {
		t.Fatalf("expected vod1 to be kept, but was filtered")
	}
	if cleaned.Name != "肖申克的救赎" {
		t.Errorf("expected clean name 肖申克的救赎, got %s", cleaned.Name)
	}
	if cleaned.TargetTypeID != 100 || cleaned.TargetTypeName != "大电影" {
		t.Errorf("expected target category 100/大电影, got %d/%s", cleaned.TargetTypeID, cleaned.TargetTypeName)
	}
	if len(cleaned.PlayGroups) != 1 || cleaned.PlayGroups[0].PlayerCode != "m3u8" {
		t.Errorf("expected play group m3u8, got %+v", cleaned.PlayGroups)
	}
	if cleaned.Content != "这是一部伟大的电影。" {
		t.Errorf("expected cleaned content, got %s", cleaned.Content)
	}

	// 测试用例 2: 命中黑名单词过滤 (预告片)
	vod2 := VodItem{
		VodID:       FlexInt(1002),
		VodName:     "阿凡达3 预告片",
		TypeID:      FlexInt(1),
		VodPlayURL:  "预告$https://test.com/preview.m3u8",
		VodPlayFrom: "m3u8",
	}
	_, ok2 := fe.CleanAndTransform(vod2)
	if ok2 {
		t.Errorf("expected vod2 to be dropped due to keyword, but passed")
	}

	// 测试用例 3: 无播放链接
	vod3 := VodItem{
		VodID:   FlexInt(1003),
		VodName: "无源电影",
		TypeID:  FlexInt(1),
	}
	_, ok3 := fe.CleanAndTransform(vod3)
	if ok3 {
		t.Errorf("expected vod3 to be dropped due to RequirePlayURLs, but passed")
	}
}
