package api

import (
	"context"
	"net/url"
	"strconv"
	"strings"
	"testing"

	"video-collection-service/pkg/store"
)

func TestDanmakuTimelineAndProfileUpdate(t *testing.T) {
	f := newContentFixture(t)
	videoID, err := f.s.SaveVideoManual(context.Background(), &store.VideoRecord{Name: "弹幕测试片"})
	if err != nil {
		t.Fatal(err)
	}
	episode := "0:第1话"
	query := "/api/danmaku?video_id=" + strconv.Itoa(videoID) + "&episode_key=" + url.QueryEscape(episode)
	empty := decodeContentData[[]store.Danmaku](t, f.request("GET", query, "", nil, 200))
	if len(empty) != 0 {
		t.Fatalf("expected empty danmaku, got %+v", empty)
	}
	f.request("POST", "/api/danmaku", `{"video_id":1,"episode_key":"0:第1话","content":"你好"}`, nil, 401)

	body := `{"video_id":` + strconv.Itoa(videoID) + `,"episode_key":"0:第1话","play_time_ms":1500,"mode":0,"color":"#ff6b9a","content":"这一话好好看"}`
	created := decodeContentData[store.Danmaku](t, f.request("POST", "/api/danmaku", body, f.alice, 200))
	if created.Color != "#FF6B9A" || created.PlayTimeMs != 1500 || created.AuthorName != "小爱" {
		t.Fatalf("bad danmaku: %+v", created)
	}
	listed := decodeContentData[[]store.Danmaku](t, f.request("GET", query, "", nil, 200))
	if len(listed) != 1 || listed[0].ID != created.ID {
		t.Fatalf("list mismatch: %+v", listed)
	}
	f.request("POST", "/api/danmaku", `{"video_id":`+strconv.Itoa(videoID)+`,"episode_key":"0:第1话","content":"颜色不对","color":"#000000"}`, f.alice, 400)
	f.request("POST", "/api/danmaku", `{"video_id":`+strconv.Itoa(videoID)+`,"episode_key":"0:第1话","content":"`+strings.Repeat("弹", 41)+`"}`, f.alice, 400)
	f.request("POST", "/api/danmaku", `{"video_id":999999,"episode_key":"0:第1话","content":"没有这部"}`, f.alice, 404)
	f.request("DELETE", "/api/danmaku?id="+strconv.Itoa(created.ID), "", f.bob, 403)
	f.request("DELETE", "/api/danmaku?id="+strconv.Itoa(created.ID), "", f.alice, 200)
	f.request("DELETE", "/api/danmaku?id="+strconv.Itoa(created.ID), "", f.alice, 404)

	updated := decodeContentData[map[string]any](t, f.request("POST", "/api/me", `{"nickname":"星空旅人","avatar":"https://cdn.example.com/a.png","bio":"喜欢在夜里追番"}`, f.alice, 200))
	if updated["nickname"] != "星空旅人" || updated["bio"] != "喜欢在夜里追番" || updated["profile_avatar"] != "https://cdn.example.com/a.png" {
		t.Fatalf("profile not saved: %+v", updated)
	}
	again := decodeContentData[map[string]any](t, f.request("GET", "/api/me", "", f.alice, 200))
	if again["nickname"] != "星空旅人" || again["role"] != "user" {
		t.Fatalf("profile readback: %+v", again)
	}
	f.request("POST", "/api/me", `{"nickname":"","avatar":"","bio":""}`, f.alice, 400)
	f.request("POST", "/api/me", `{"nickname":"旅人","avatar":"javascript:alert(1)","bio":""}`, f.alice, 400)
	f.request("POST", "/api/me", `{"nickname":"旅人","avatar":"","bio":"","role":"admin"}`, f.alice, 400)
}
