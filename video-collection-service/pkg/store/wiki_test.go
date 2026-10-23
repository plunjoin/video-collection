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

func TestWikiSyncRefreshAndLiveCast(t *testing.T) {
	ctx := context.Background()
	s := newTestSQLiteStore(t)
	vod := &collector.CleanedVod{Name: "同步作品", Actor: "演员甲、演员乙", Director: "导演甲"}
	vid, err := s.UpsertVideo(ctx, "test", vod)
	if err != nil {
		t.Fatal(err)
	}
	sub, err := s.SyncVideoToWikiSubject(ctx, vid)
	if err != nil {
		t.Fatal(err)
	}

	// A later collection fills only missing work metadata.
	vod.Picture = "https://example.com/work.jpg"
	vod.Content = "采集简介"
	vod.Year = "2026"
	vod.Area = "中国"
	vod.Language = "中文"
	vod.Remarks = "完结"
	if _, err := s.SaveVideoManual(ctx, &VideoRecord{ID: vid, Name: vod.Name, Actor: vod.Actor, Director: vod.Director, Picture: vod.Picture, Content: vod.Content, Year: vod.Year, Area: vod.Area, Language: vod.Language, Remarks: vod.Remarks}); err != nil {
		t.Fatal(err)
	}
	refreshed, err := s.SyncVideoToWikiSubject(ctx, vid)
	if err != nil {
		t.Fatal(err)
	}
	if refreshed.ID != sub.ID || refreshed.Summary != vod.Content || refreshed.CoverImage != vod.Picture {
		t.Fatalf("missing work metadata not refreshed: %+v", refreshed)
	}
	if refreshed.Infobox["year"] != "2026" || refreshed.Infobox["area"] != "中国" || refreshed.Infobox["language"] != "中文" || refreshed.Infobox["remarks"] != "完结" {
		t.Fatalf("missing infobox keys not filled: %+v", refreshed.Infobox)
	}
	cast, err := s.ListWikiCastForVideo(ctx, vid)
	if err != nil {
		t.Fatal(err)
	}
	if len(cast) != 3 || cast[0].Name != "演员甲" || cast[1].Name != "演员乙" || cast[2].RelationType != "director" || cast[0].SubjectID <= 0 {
		t.Fatalf("unexpected ordered cast: %+v", cast)
	}
	person, err := s.GetWikiSubjectByID(ctx, cast[0].SubjectID)
	if err != nil {
		t.Fatal(err)
	}
	person.Summary = "管理员人物简介"
	person.CoverImage = "https://example.com/person.jpg"
	person.OriginalName = "Actor A"
	if err := s.UpdateWikiSubject(ctx, &person.WikiSubject); err != nil {
		t.Fatal(err)
	}
	refreshed.Name = "管理员改名"
	refreshed.Summary = "管理员作品简介"
	refreshed.CoverImage = "https://example.com/admin.jpg"
	refreshed.Infobox["year"] = "编辑年份"
	refreshed.Infobox["area"] = "编辑地区"
	refreshed.Infobox["language"] = "编辑语言"
	refreshed.Infobox["remarks"] = "编辑备注"
	refreshed.Infobox["custom"] = "保留字段"
	if err := s.UpdateWikiSubject(ctx, refreshed); err != nil {
		t.Fatal(err)
	}
	editedAt := refreshed.UpdatedAt
	again, err := s.SyncVideoToWikiSubject(ctx, vid)
	if err != nil {
		t.Fatal(err)
	}
	if again.ID != sub.ID || again.Name != refreshed.Name || again.Summary != refreshed.Summary || again.CoverImage != refreshed.CoverImage || !again.UpdatedAt.Equal(editedAt) {
		t.Fatalf("re-sync overwrote edited work or unnecessarily updated it: %+v", again)
	}
	for key, want := range refreshed.Infobox {
		if again.Infobox[key] != want {
			t.Errorf("infobox %s overwritten: %v", key, again.Infobox[key])
		}
	}
	cast, err = s.ListWikiCastForSubject(ctx, sub.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(cast) != 3 || cast[0].Summary != person.Summary || cast[0].CoverImage != person.CoverImage || cast[0].OriginalName != person.OriginalName {
		t.Fatalf("cast must read edited Wiki metadata without duplicating relations: %+v", cast)
	}
	video, err := s.GetVideoByID(ctx, vid)
	if err != nil || video.SubjectID != sub.ID {
		t.Fatalf("missing video subject ID: %+v, %v", video, err)
	}
	detail, err := s.GetWikiSubjectByID(ctx, sub.ID)
	if err != nil {
		t.Fatal(err)
	}
	if detail.ForwardRelations[0].TargetSubject.Summary != person.Summary || detail.ForwardRelations[0].TargetSubject.CoverImage != person.CoverImage {
		t.Fatalf("missing forward relation metadata: %+v", detail.ForwardRelations[0])
	}
	person, err = s.GetWikiSubjectByID(ctx, cast[0].SubjectID)
	if err != nil {
		t.Fatal(err)
	}
	work := person.ReverseRelations[0].SourceSubject
	if work.Summary != refreshed.Summary || work.CoverImage != refreshed.CoverImage {
		t.Fatalf("missing reverse relation metadata: %+v", work)
	}
	empty, err := s.ListWikiCastForSubject(ctx, 0)
	if err != nil || empty == nil || len(empty) != 0 {
		t.Fatalf("expected empty cast array: %v, %v", empty, err)
	}
}

func TestWikiCastIncludesPersonRelationsAndExcludesUnrelatedSubjects(t *testing.T) {
	s := newTestSQLiteStore(t)
	ctx := context.Background()
	work := &WikiSubject{Name: "关系筛选作品", Type: "work"}
	if _, err := s.CreateWikiSubject(ctx, work); err != nil {
		t.Fatal(err)
	}
	for _, item := range []struct {
		name, subjectType, relation string
		order                       int
	}{
		{"纪元", "event", "belongs_to_era", 0},
		{"动作监督", "person", "action_director", 0},
		{"配音演员", "person", "cv", 4},
		{"皮套演员", "person", "suit_actor", 2},
	} {
		target := &WikiSubject{Name: item.name, Type: item.subjectType}
		if _, err := s.CreateWikiSubject(ctx, target); err != nil {
			t.Fatal(err)
		}
		if _, err := s.CreateWikiRelation(ctx, &WikiRelation{SourceID: work.ID, TargetID: target.ID, RelationType: item.relation, SortOrder: item.order, RoleDescription: "编辑角色"}); err != nil {
			t.Fatal(err)
		}
	}
	cast, err := s.ListWikiCastForSubject(ctx, work.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(cast) != 3 || cast[0].Name != "皮套演员" || cast[1].Name != "配音演员" || cast[2].Name != "动作监督" || cast[0].RoleDescription != "编辑角色" {
		t.Fatalf("unexpected cast filter/order: %+v", cast)
	}
}


func TestSyncVideoToWikiFillsPersonCoverFromCollection(t *testing.T) {
	ctx := context.Background()
	s := newTestSQLiteStore(t)

	_, err := s.SaveCollectionRecord(ctx, CollectionRecord{
		SourceID: "person_src",
		Target:   "record",
		Key:      "actor_zhangyi",
		Values: map[string]string{
			"name":      "张译",
			"avatar":    "https://cdn.example.com/zhangyi.jpg",
			"biography": "实力派演员",
			"role_type": "actor",
		},
	}, false)
	if err != nil {
		t.Fatal(err)
	}

	vid, err := s.UpsertVideo(ctx, "vod_src", &collector.CleanedVod{
		Name:    "狂飙采集对接",
		Picture: "https://cdn.example.com/work.jpg",
		Actor:   "张译,李一桐",
		Content: "扫黑除恶",
	})
	if err != nil || vid <= 0 {
		t.Fatalf("UpsertVideo: %v id=%d", err, vid)
	}

	// UpsertVideo auto-syncs; cast must expose collection avatar.
	cast, err := s.ListWikiCastForVideo(ctx, vid)
	if err != nil {
		t.Fatal(err)
	}
	if len(cast) < 2 {
		t.Fatalf("expected cast members, got %+v", cast)
	}
	var zhangyi *WikiCastMember
	for i := range cast {
		if cast[i].Name == "张译" {
			zhangyi = &cast[i]
			break
		}
	}
	if zhangyi == nil {
		t.Fatalf("missing 张译 in cast: %+v", cast)
	}
	if zhangyi.CoverImage != "https://cdn.example.com/zhangyi.jpg" {
		t.Fatalf("expected collection avatar on cast card, got %q", zhangyi.CoverImage)
	}
	if zhangyi.Summary != "实力派演员" {
		t.Fatalf("expected biography summary, got %q", zhangyi.Summary)
	}

	work, err := s.GetWikiSubjectByName(ctx, "狂飙采集对接")
	if err != nil || work == nil || work.CoverImage != "https://cdn.example.com/work.jpg" {
		t.Fatalf("work cover not wired: %+v err=%v", work, err)
	}
}

func TestRectifyPersonToWikiDoesNotOverwriteEditedCover(t *testing.T) {
	ctx := context.Background()
	s := newTestSQLiteStore(t)

	person := &WikiSubject{Name: "简秀吉", Type: "person", SubType: "actor", CoverImage: "https://admin.example/cover.jpg", Summary: "管理员简介"}
	if _, err := s.CreateWikiSubject(ctx, person); err != nil {
		t.Fatal(err)
	}
	_, err := s.SaveCollectionRecord(ctx, CollectionRecord{
		SourceID: "p", Target: "record", Key: "k1",
		Values: map[string]string{"name": "简秀吉", "avatar": "https://collect.example/new.jpg", "biography": "采集简介"},
	}, false)
	if err != nil {
		t.Fatal(err)
	}
	out, err := s.RectifyCollectionRecordToWiki(ctx, "p", "record", "k1", WikiSubject{
		Name: "简秀吉", Type: "person", SubType: "actor",
		CoverImage: "https://collect.example/new.jpg", Summary: "采集简介",
	})
	if err != nil {
		t.Fatal(err)
	}
	if out.CoverImage != "https://admin.example/cover.jpg" || out.Summary != "管理员简介" {
		t.Fatalf("rectify overwrote edited fields: %+v", out)
	}
}

func TestRectifyVideoWiresWikiCast(t *testing.T) {
	ctx := context.Background()
	s := newTestSQLiteStore(t)
	_, err := s.SaveCollectionRecord(ctx, CollectionRecord{
		SourceID: "vsrc", Target: "record", Key: "geats",
		Values: map[string]string{
			"name": "假面骑士极狐对接", "title": "假面骑士极狐对接",
			"cover": "https://cdn.example.com/geats.jpg",
			"actor": "简秀吉", "play_url": "https://cdn.example.com/1.m3u8", "play_from": "m3u8",
		},
	}, false)
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.SaveCollectionRecord(ctx, CollectionRecord{
		SourceID: "psrc", Target: "record", Key: "actor_kaneshiro",
		Values: map[string]string{"name": "简秀吉", "avatar": "https://cdn.example.com/kaneshiro.jpg", "biography": "主演"},
	}, false)
	if err != nil {
		t.Fatal(err)
	}

	vod := &collector.CleanedVod{
		Name: "假面骑士极狐对接", Picture: "https://cdn.example.com/geats.jpg",
		Actor: "简秀吉", PlayGroups: []collector.PlayGroup{{PlayerCode: "m3u8", Episodes: []collector.Episode{{Name: "01", URL: "https://cdn.example.com/1.m3u8"}}}},
	}
	vid, err := s.RectifyCollectionRecordToVideo(ctx, "vsrc", "record", "geats", vod)
	if err != nil || vid <= 0 {
		t.Fatalf("rectify video: %v id=%d", err, vid)
	}
	cast, err := s.ListWikiCastForVideo(ctx, vid)
	if err != nil {
		t.Fatal(err)
	}
	if len(cast) != 1 || cast[0].Name != "简秀吉" || cast[0].CoverImage != "https://cdn.example.com/kaneshiro.jpg" {
		t.Fatalf("expected wired cast with cover: %+v", cast)
	}
}
