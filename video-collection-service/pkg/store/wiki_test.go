package store

import (
	"context"
	"path/filepath"
	"testing"

	"video-collection-service/pkg/collector"
)

func newTestSQLiteStore(t *testing.T) Store {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "test_wiki.db")
	s, err := NewSQLiteStore(dbPath)
	if err != nil {
		t.Fatalf("failed to create sqlite store: %v", err)
	}
	t.Cleanup(func() { _ = s.Close() })
	return s
}

func TestWikiSubjectsRelationsAndGraph(t *testing.T) {
	ctx := context.Background()
	s := newTestSQLiteStore(t)

	// 1. 创建特摄作品词条
	kuuga := &WikiSubject{
		Name:         "假面骑士空我",
		OriginalName: "仮面ライダークウガ",
		Type:         "work",
		SubType:      "tokusatsu",
		Summary:      "平成假面骑士首作，讲述五代雄介变身空我对抗未确认生命体的英雄物语。",
		CoverImage:   "https://example.com/kuuga.jpg",
		Infobox: map[string]any{
			"首播时间": "2000-01-30",
			"集数":   49,
			"制作公司": "东映株式会社",
		},
		Aliases: []string{"Masked Rider Kuuga", "Kamen Rider Kuuga"},
	}
	kuugaID, err := s.CreateWikiSubject(ctx, kuuga)
	if err != nil || kuugaID <= 0 {
		t.Fatalf("CreateWikiSubject failed: %v", err)
	}

	// 2. 创建真实人物：人间体演员（小田切让）
	odagiri := &WikiSubject{
		Name:         "小田切让",
		OriginalName: "オダギリジョー",
		Type:         "person",
		SubType:      "actor",
		Summary:      "日本知名影视男演员、导演。",
		Infobox: map[string]any{
			"出生地": "日本冈山县津山市",
			"出生日期": "1976-02-16",
		},
	}
	odagiriID, err := s.CreateWikiSubject(ctx, odagiri)
	if err != nil {
		t.Fatalf("CreateWikiSubject actor failed: %v", err)
	}

	// 3. 创建特摄专业工种：皮套演员（富永研司）
	tominaga := &WikiSubject{
		Name:         "富永研司",
		OriginalName: "Kenji Tominaga",
		Type:         "person",
		SubType:      "suit_actor",
		Summary:      "日本特摄皮套演员、特技动作演员，空我主角皮套担当。",
	}
	tominagaID, err := s.CreateWikiSubject(ctx, tominaga)
	if err != nil {
		t.Fatalf("CreateWikiSubject suit_actor failed: %v", err)
	}

	// 4. 创建动作监督/武指（金田治）
	kaneda := &WikiSubject{
		Name:         "金田治",
		OriginalName: "Osamu Kaneda",
		Type:         "person",
		SubType:      "martial_arts",
		Summary:      "日本动作监督、电影导演，日本Action Enterprise社长。",
	}
	kanedaID, err := s.CreateWikiSubject(ctx, kaneda)
	if err != nil {
		t.Fatalf("CreateWikiSubject martial_arts failed: %v", err)
	}

	// 5. 创建纪元时间线词条：平成假面骑士
	heiseiEra := &WikiSubject{
		Name:    "平成假面骑士年代",
		Type:    "event",
		SubType: "era",
		Summary: "2000年至2019年间由东映制作播出的20部新世代假面骑士全系列。",
	}
	heiseiID, err := s.CreateWikiSubject(ctx, heiseiEra)
	if err != nil {
		t.Fatalf("CreateWikiSubject era failed: %v", err)
	}

	// 6. 建立多维拓扑关系网
	relations := []WikiRelation{
		{SourceID: kuugaID, TargetID: odagiriID, RelationType: "actor", RoleDescription: "饰演人间体: 五代雄介"},
		{SourceID: kuugaID, TargetID: tominagaID, RelationType: "suit_actor", RoleDescription: "空我全形态皮套演职"},
		{SourceID: kuugaID, TargetID: kanedaID, RelationType: "action_director", RoleDescription: "动作监督 / 武指"},
		{SourceID: kuugaID, TargetID: heiseiID, RelationType: "belongs_to_era", RoleDescription: "平成第一作"},
	}

	for _, rel := range relations {
		r := rel
		rID, err := s.CreateWikiRelation(ctx, &r)
		if err != nil || rID <= 0 {
			t.Fatalf("CreateWikiRelation failed: %v", err)
		}
	}

	// 7. 查询词条详情聚合视图 (GetWikiSubjectByID)
	detail, err := s.GetWikiSubjectByID(ctx, kuugaID)
	if err != nil {
		t.Fatalf("GetWikiSubjectByID failed: %v", err)
	}
	if detail.Name != "假面骑士空我" {
		t.Errorf("expected name 假面骑士空我, got %s", detail.Name)
	}
	if len(detail.ForwardRelations) != 4 {
		t.Errorf("expected 4 forward relations, got %d", len(detail.ForwardRelations))
	}

	// 8. 反向反查验证：查询皮套演员富永研司的详情，应包含反向参演的作品
	tominagaDetail, err := s.GetWikiSubjectByID(ctx, tominagaID)
	if err != nil {
		t.Fatalf("GetWikiSubjectByID tominaga failed: %v", err)
	}
	if len(tominagaDetail.ReverseRelations) != 1 {
		t.Fatalf("expected 1 reverse relation for suit_actor, got %d", len(tominagaDetail.ReverseRelations))
	}
	if tominagaDetail.ReverseRelations[0].SourceSubject.Name != "假面骑士空我" {
		t.Errorf("expected reverse relation to link to 假面骑士空我, got %s", tominagaDetail.ReverseRelations[0].SourceSubject.Name)
	}

	// 9. 图谱拓扑提取验证 (GetWikiGraph)
	graph, err := s.GetWikiGraph(ctx, kuugaID, 1)
	if err != nil {
		t.Fatalf("GetWikiGraph failed: %v", err)
	}
	if len(graph.Nodes) != 5 {
		t.Errorf("expected 5 nodes in graph (1 center + 4 neighbors), got %d", len(graph.Nodes))
	}
	if len(graph.Edges) != 4 {
		t.Errorf("expected 4 edges in graph, got %d", len(graph.Edges))
	}

	// 10. 分页检索与关键词过滤 (ListWikiSubjects)
	list, total, err := s.ListWikiSubjects(ctx, WikiSubjectQuery{
		Page:     1,
		PageSize: 10,
		Type:     "person",
		Keyword:  "富永",
	})
	if err != nil || total != 1 || len(list) != 1 {
		t.Fatalf("ListWikiSubjects search failed: total=%d, err=%v", total, err)
	}
	if list[0].Name != "富永研司" {
		t.Errorf("expected 富永研司, got %s", list[0].Name)
	}
}

func TestSyncVideoToWikiSubject(t *testing.T) {
	ctx := context.Background()
	s := newTestSQLiteStore(t)

	// 模拟已采集入库的经典影视
	vod := &collector.CleanedVod{
		Name:     "狂飙",
		SubName:  "The Knockout",
		Picture:  "https://example.com/kuangbiao.jpg",
		Actor:    "张译, 张颂文, 李一桐, 高叶",
		Director: "徐纪周",
		Area:     "中国大陆",
		Language: "汉语普通话",
		Year:     "2023",
		Remarks:  "完结39集",
		Content:  "京海市扫黑除恶大戏...",
		PlayGroups: []collector.PlayGroup{
			{PlayerCode: "m3u8", Episodes: []collector.Episode{{Name: "第1集", URL: "https://example.com/1.m3u8"}}},
		},
	}
	vid, err := s.UpsertVideo(ctx, "test_src", vod)
	if err != nil || vid <= 0 {
		t.Fatalf("UpsertVideo failed: %v", err)
	}

	// 触发智能同步与冷启动
	sub, err := s.SyncVideoToWikiSubject(ctx, vid)
	if err != nil {
		t.Fatalf("SyncVideoToWikiSubject failed: %v", err)
	}
	if sub.Name != "狂飙" {
		t.Errorf("expected subject name 狂飙, got %s", sub.Name)
	}

	// 校验生成的作品词条详情
	detail, err := s.GetWikiSubjectByID(ctx, sub.ID)
	if err != nil {
		t.Fatalf("GetWikiSubjectByID failed: %v", err)
	}
	// 4位演员 + 1位导演 = 5个演职关系
	if len(detail.ForwardRelations) != 5 {
		t.Errorf("expected 5 forward relations (4 actors + 1 director), got %d", len(detail.ForwardRelations))
	}
	// 校验自动绑定的线上播放视频
	if len(detail.LinkedVideos) != 1 || detail.LinkedVideos[0].ID != vid {
		t.Errorf("expected linked video %d, got %v", vid, detail.LinkedVideos)
	}

	// 校验演职员节点是否已自动建档
	zhangyi, err := s.GetWikiSubjectByName(ctx, "张译")
	if err != nil || zhangyi == nil {
		t.Fatalf("expected actor node 张译 to exist, got %v", zhangyi)
	}
	if zhangyi.Type != "person" || zhangyi.SubType != "actor" {
		t.Errorf("expected 张译 to be person/actor, got %s/%s", zhangyi.Type, zhangyi.SubType)
	}

	xujizhou, err := s.GetWikiSubjectByName(ctx, "徐纪周")
	if err != nil || xujizhou == nil {
		t.Fatalf("expected director node 徐纪周 to exist, got %v", xujizhou)
	}
	if xujizhou.Type != "person" || xujizhou.SubType != "director" {
		t.Errorf("expected 徐纪周 to be person/director, got %s/%s", xujizhou.Type, xujizhou.SubType)
	}
}
