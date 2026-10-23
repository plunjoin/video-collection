package api

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"video-collection-service/pkg/collector"
	"video-collection-service/pkg/store"
)

func TestWikiAPIEndpoints(t *testing.T) {
	f := newContentFixture(t)
	ctx := context.Background()

	// 1. 权限测试：普通用户与匿名用户不可操作管理员专属接口
	f.request("POST", "/api/admin/wiki/subjects", `{}`, nil, 401)
	f.request("POST", "/api/admin/wiki/subjects", `{}`, f.alice, 401)
	f.request("POST", "/api/admin/wiki/relations", `{}`, f.alice, 401)
	f.request("POST", "/api/admin/wiki/sync-video", `{}`, f.alice, 401)

	// 2. 管理员创建特摄作品词条
	subjectJSON := `{
		"name": "假面骑士极狐",
		"original_name": "仮面ライダーギーツ",
		"type": "work",
		"sub_type": "tokusatsu",
		"summary": "生存游戏欲望大奖赛（DGP）开幕，浮世英寿化身极狐角逐胜利。",
		"infobox": {"首播时间": "2022-09-04", "编剧": "高桥悠也"}
	}`
	res := f.request("POST", "/api/admin/wiki/subjects", subjectJSON, f.admin, 200)
	var geatsID int
	if err := json.Unmarshal(res["id"], &geatsID); err != nil || geatsID <= 0 {
		t.Fatalf("expected subject ID > 0, got %d, err=%v", geatsID, err)
	}

	// 3. 管理员创建皮套演员词条（绳田雄哉）
	suitActorJSON := `{
		"name": "绳田雄哉",
		"type": "person",
		"sub_type": "suit_actor",
		"summary": "日本JAE特摄动作演员，极狐主角皮套演员。"
	}`
	res2 := f.request("POST", "/api/admin/wiki/subjects", suitActorJSON, f.admin, 200)
	var nawataID int
	if err := json.Unmarshal(res2["id"], &nawataID); err != nil || nawataID <= 0 {
		t.Fatalf("expected subject ID > 0, got %d, err=%v", nawataID, err)
	}

	// 4. 建立关系：极狐 -> 绳田雄哉 (suit_actor)
	relJSON := fmt.Sprintf(`{
		"source_id": %d,
		"target_id": %d,
		"relation_type": "suit_actor",
		"role_description": "假面骑士Geats 主角皮套演员"
	}`, geatsID, nawataID)
	f.request("POST", "/api/admin/wiki/relations", relJSON, f.admin, 200)

	// 5. 公开接口：检索词条详情 (包含关系)
	detailRes := f.request("GET", fmt.Sprintf("/api/wiki/subject?id=%d", geatsID), "", nil, 200)
	detail := decodeContentData[store.WikiSubjectDetail](t, detailRes)
	if detail.Name != "假面骑士极狐" {
		t.Errorf("expected 假面骑士极狐, got %s", detail.Name)
	}
	if len(detail.ForwardRelations) != 1 {
		t.Fatalf("expected 1 forward relation, got %d", len(detail.ForwardRelations))
	}
	if detail.ForwardRelations[0].TargetSubject.Name != "绳田雄哉" {
		t.Errorf("expected target subject 绳田雄哉, got %s", detail.ForwardRelations[0].TargetSubject.Name)
	}

	// 6. 公开接口：获取知识图谱可视化数据
	graphRes := f.request("GET", fmt.Sprintf("/api/wiki/graph?id=%d&depth=1", geatsID), "", nil, 200)
	graph := decodeContentData[store.WikiGraphData](t, graphRes)
	if len(graph.Nodes) != 2 {
		t.Errorf("expected 2 nodes in graph, got %d", len(graph.Nodes))
	}
	if len(graph.Edges) != 1 {
		t.Errorf("expected 1 edge in graph, got %d", len(graph.Edges))
	}

	// 7. 公开接口：关键词与类型复合检索列表
	listRes := f.request("GET", "/api/wiki/subjects?keyword=极狐&type=work", "", nil, 200)
	list := decodeContentData[[]store.WikiSubject](t, listRes)
	if len(list) != 1 || list[0].Name != "假面骑士极狐" {
		t.Errorf("expected 1 result, got %v", list)
	}

	// 8. 视频库一键冷启动同步为 Wiki 词条与演职员关系测试
	vid, err := f.s.UpsertVideo(ctx, "test_src", &collector.CleanedVod{
		Name:           "流浪地球2",
		SubName:        "The Wandering Earth II",
		Actor:          "吴京, 刘德华, 李雪健",
		Director:       "郭帆",
		TargetTypeName: "科幻片",
		Year:           "2023",
	})
	if err != nil || vid <= 0 {
		t.Fatalf("UpsertVideo failed: %v", err)
	}

	syncRes := f.request("POST", "/api/admin/wiki/sync-video", fmt.Sprintf(`{"video_id": %d}`, vid), f.admin, 200)
	var syncData struct {
		Subject *store.WikiSubject `json:"subject"`
	}
	_ = json.Unmarshal(syncRes["subject"], &syncData.Subject)
	if syncData.Subject == nil || syncData.Subject.Name != "流浪地球2" {
		t.Fatalf("expected synced subject 流浪地球2, got %v", syncData.Subject)
	}

	// 验证吴京、郭帆是否自动建档并挂载关系
	wujing, err := f.s.GetWikiSubjectByName(ctx, "吴京")
	if err != nil || wujing == nil {
		t.Fatalf("expected actor node 吴京 to be auto-created")
	}
	guofan, err := f.s.GetWikiSubjectByName(ctx, "郭帆")
	if err != nil || guofan == nil {
		t.Fatalf("expected director node 郭帆 to be auto-created")
	}
}

func TestVideoDetailWikiCastTracksAdminEdits(t *testing.T) {
	f := newContentFixture(t)
	vid, err := f.s.UpsertVideo(context.Background(), "test", &collector.CleanedVod{Name: "演职员测试", Actor: "测试演员"})
	if err != nil {
		t.Fatal(err)
	}
	endpoint := fmt.Sprintf("/api/video?id=%d", vid)
	before := f.request("GET", endpoint, "", nil, 200)
	if string(before["cast"]) != "[]" || string(before["subject_id"]) != "0" {
		t.Fatalf("unsynced detail: %v", before)
	}
	video := decodeContentData[store.VideoRecord](t, before)
	if video.SubjectID != 0 {
		t.Fatal("unexpected subject")
	}
	f.request("POST", "/api/admin/wiki/sync-video", fmt.Sprintf(`{"video_id":%d}`, vid), f.admin, 200)
	res := f.request("GET", endpoint, "", nil, 200)
	video = decodeContentData[store.VideoRecord](t, res)
	var subjectID int
	if err := json.Unmarshal(res["subject_id"], &subjectID); err != nil {
		t.Fatal(err)
	}
	var cast []store.WikiCastMember
	if err := json.Unmarshal(res["cast"], &cast); err != nil {
		t.Fatal(err)
	}
	if video.SubjectID <= 0 || subjectID != video.SubjectID || len(cast) != 1 || cast[0].SubjectID <= 0 || cast[0].Name != "测试演员" {
		t.Fatalf("missing wiki cast: video=%+v cast=%+v", video, cast)
	}
	personID := cast[0].SubjectID
	f.request("PUT", "/api/admin/wiki/subjects", fmt.Sprintf(`{"id":%d,"name":"测试演员","type":"person","sub_type":"actor","summary":"更新人物简介","cover_image":"https://example.com/actor.jpg"}`, personID), f.admin, 200)
	res = f.request("GET", endpoint, "", nil, 200)
	if err := json.Unmarshal(res["cast"], &cast); err != nil {
		t.Fatal(err)
	}
	if cast[0].Summary != "更新人物简介" || cast[0].CoverImage != "https://example.com/actor.jpg" {
		t.Fatalf("stale cast: %+v", cast)
	}
	workRes := f.request("GET", fmt.Sprintf("/api/wiki/subject?id=%d", video.SubjectID), "", nil, 200)
	work := decodeContentData[store.WikiSubjectDetail](t, workRes)
	if work.ForwardRelations[0].TargetSubject.Summary != cast[0].Summary {
		t.Fatal("nested relation missing bio")
	}
	personRes := f.request("GET", fmt.Sprintf("/api/wiki/subject?id=%d", personID), "", nil, 200)
	person := decodeContentData[store.WikiSubjectDetail](t, personRes)
	if len(person.ReverseRelations) != 1 || person.ReverseRelations[0].SourceSubject.ID != video.SubjectID {
		t.Fatalf("missing related works: %+v", person)
	}
	f.request("DELETE", fmt.Sprintf("/api/admin/wiki/relations?id=%d", work.ForwardRelations[0].ID), "", f.admin, 200)
	res = f.request("GET", endpoint, "", nil, 200)
	if string(res["cast"]) != "[]" {
		t.Fatal("removed Wiki relation still in cast")
	}
}
