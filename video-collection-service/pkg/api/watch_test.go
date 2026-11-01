package api

import (
	"bufio"
	"context"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"

	"video-collection-service/pkg/collector"
	"video-collection-service/pkg/store"
)

type watchMemberView struct {
	UserID   int    `json:"user_id"`
	Nickname string `json:"nickname"`
	IsHost   bool   `json:"is_host"`
}

type watchSnapshot struct {
	Code             string               `json:"code"`
	VideoID          int                  `json:"video_id"`
	GroupIndex       int                  `json:"group_index"`
	EpisodeIndex     int                  `json:"episode_index"`
	Title            string               `json:"title"`
	HostID           int                  `json:"host_id"`
	Version          int64                `json:"version"`
	Playing          bool                 `json:"playing"`
	PositionMs       int64                `json:"position_ms"`
	TargetPositionMs int64                `json:"target_position_ms"`
	ControlMode      string               `json:"control_mode"`
	ViewerIsHost     bool                 `json:"viewer_is_host"`
	Members          []watchMemberView    `json:"members"`
	Messages         []store.WatchMessage `json:"messages"`
}

func saveWatchVideo(t *testing.T, f *contentFixture) int {
	t.Helper()
	videoID, err := f.s.SaveVideoManual(context.Background(), &store.VideoRecord{
		Name: "一起看测试片",
		PlayGroups: []collector.PlayGroup{{
			PlayerCode: "m3u8",
			Episodes: []collector.Episode{
				{Name: "第01话", URL: "https://example.com/01.m3u8"},
				{Name: "第02话", URL: "https://example.com/02.m3u8"},
			},
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	return videoID
}

func TestWatchRoomFlow(t *testing.T) {
	f := newContentFixture(t)
	videoID := saveWatchVideo(t, f)

	// 未登录与参数校验
	f.request("POST", "/api/watch/rooms", `{"video_id":1}`, nil, 401)
	f.request("POST", "/api/watch/rooms", `{"video_id":999999}`, f.alice, 404)
	f.request("POST", "/api/watch/rooms", `{"video_id":`+itoa(videoID)+`,"group_index":5}`, f.alice, 400)
	f.request("POST", "/api/watch/rooms", `{"video_id":`+itoa(videoID)+`,"episode_index":9}`, f.alice, 400)

	// 建房
	created := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms",
		`{"video_id":`+itoa(videoID)+`,"group_index":0,"episode_index":0}`, f.alice, 200))
	if len(created.Code) != 6 || !created.ViewerIsHost || created.HostID != f.alice.ID {
		t.Fatalf("bad created room: %+v", created)
	}
	if created.Title != "一起看测试片 · 第01话" {
		t.Fatalf("bad title: %q", created.Title)
	}
	if len(created.Members) != 1 || created.Members[0].UserID != f.alice.ID {
		t.Fatalf("bad members: %+v", created.Members)
	}

	// 房间码校验
	f.request("GET", "/api/watch/rooms?code=AB", "", f.bob, 400)
	f.request("GET", "/api/watch/rooms?code=ZZZZZZ", "", f.bob, 404)

	// bob 加入
	joined := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/join",
		`{"code":"`+created.Code+`"}`, f.bob, 200))
	if joined.ViewerIsHost || joined.HostID != f.alice.ID || len(joined.Members) != 2 {
		t.Fatalf("bad join snapshot: %+v", joined)
	}

	// bob 心跳在线
	beat := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/heartbeat",
		`{"code":"`+created.Code+`","position_ms":1500,"since_msg_id":0}`, f.bob, 200))
	if len(beat.Members) != 2 {
		t.Fatalf("heartbeat members: %+v", beat.Members)
	}

	// 非房主不能控制播放
	f.request("POST", "/api/watch/rooms/state",
		`{"code":"`+created.Code+`","playing":true,"position_ms":60000}`, f.bob, 403)

	// 房主播放并切集，成员心跳应看到目标进度随时间推进
	pushed := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/state",
		`{"code":"`+created.Code+`","playing":true,"position_ms":60000,"episode_index":1}`, f.alice, 200))
	if !pushed.Playing || pushed.EpisodeIndex != 1 || pushed.Version != created.Version+1 {
		t.Fatalf("bad pushed state: %+v", pushed)
	}
	beat = decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/heartbeat",
		`{"code":"`+created.Code+`","position_ms":60500,"since_msg_id":0}`, f.bob, 200))
	if !beat.Playing || beat.EpisodeIndex != 1 {
		t.Fatalf("guest state not synced: %+v", beat)
	}
	if beat.TargetPositionMs < 60000 {
		t.Fatalf("target position should advance from 60000, got %d", beat.TargetPositionMs)
	}

	// 房间聊天：bob 发言，alice 心跳增量拉取
	msg := decodeContentData[store.WatchMessage](t, f.request("POST", "/api/watch/rooms/chat",
		`{"code":"`+created.Code+`","content":"这集太燃了"}`, f.bob, 200))
	if msg.Content != "这集太燃了" || msg.AuthorName != "bob" {
		t.Fatalf("bad chat message: %+v", msg)
	}
	f.request("POST", "/api/watch/rooms/chat", `{"code":"`+created.Code+`","content":""}`, f.bob, 400)
	f.request("POST", "/api/watch/rooms/chat", `{"code":"ZZZZZZ","content":"无人房间"}`, f.bob, 404)

	beat = decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/heartbeat",
		`{"code":"`+created.Code+`","position_ms":0,"since_msg_id":0}`, f.alice, 200))
	if len(beat.Messages) != 1 || beat.Messages[0].ID != msg.ID {
		t.Fatalf("chat not delivered: %+v", beat.Messages)
	}
	// 增量：since 之后无新消息
	beat = decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/heartbeat",
		`{"code":"`+created.Code+`","position_ms":0,"since_msg_id":`+itoa(msg.ID)+`}`, f.alice, 200))
	if len(beat.Messages) != 0 {
		t.Fatalf("incremental messages should be empty: %+v", beat.Messages)
	}

	// 限频：10 秒内第 6 条被拒（此前 bob 已发 1 条）
	for i := 0; i < 4; i++ {
		f.request("POST", "/api/watch/rooms/chat", `{"code":"`+created.Code+`","content":"刷屏 `+itoa(i)+`"}`, f.bob, 200)
	}
	f.request("POST", "/api/watch/rooms/chat", `{"code":"`+created.Code+`","content":"第6条"}`, f.bob, 429)

	// 手动转让房主给 bob
	transferred := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/host",
		`{"code":"`+created.Code+`","user_id":`+itoa(f.bob.ID)+`}`, f.alice, 200))
	if transferred.HostID != f.bob.ID {
		t.Fatalf("host not transferred: %+v", transferred)
	}
	// 转让后 alice 不能再控制
	f.request("POST", "/api/watch/rooms/state",
		`{"code":"`+created.Code+`","playing":false}`, f.alice, 403)

	// bob 离开（此时是房主）→ 房主自动转让回 alice
	f.request("POST", "/api/watch/rooms/leave", `{"code":"`+created.Code+`"}`, f.bob, 200)
	afterLeave := decodeContentData[watchSnapshot](t, f.request("GET", "/api/watch/rooms?code="+created.Code, "", f.alice, 200))
	if afterLeave.HostID != f.alice.ID || len(afterLeave.Members) != 1 {
		t.Fatalf("host transfer on leave failed: %+v", afterLeave)
	}

	// alice 建新房会回收自己名下无他人活跃的旧房间
	second := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms",
		`{"video_id":`+itoa(videoID)+`}`, f.alice, 200))
	f.request("GET", "/api/watch/rooms?code="+created.Code, "", f.alice, 404)
	if second.Code == created.Code {
		t.Fatalf("new room code should differ")
	}
}

func TestWatchControlMode(t *testing.T) {
	f := newContentFixture(t)
	videoID := saveWatchVideo(t, f)

	// 建房时选择「所有人可控制」
	created := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms",
		`{"video_id":`+itoa(videoID)+`,"control_mode":"all"}`, f.alice, 200))
	if created.ControlMode != "all" {
		t.Fatalf("control_mode should be all: %+v", created)
	}
	code := created.Code
	f.request("POST", "/api/watch/rooms/join", `{"code":"`+code+`"}`, f.bob, 200)

	// 开放控制：成员可以推送播放状态
	pushed := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/state",
		`{"code":"`+code+`","playing":true,"position_ms":30000}`, f.bob, 200))
	if !pushed.Playing || pushed.PositionMs != 30000 {
		t.Fatalf("member push with mode=all failed: %+v", pushed)
	}

	// 非成员即使开放控制也不行（bob 退出后不再是成员）
	f.request("POST", "/api/watch/rooms/leave", `{"code":"`+code+`"}`, f.bob, 200)
	f.request("POST", "/api/watch/rooms/state",
		`{"code":"`+code+`","playing":false,"position_ms":0}`, f.bob, 403)
	f.request("POST", "/api/watch/rooms/join", `{"code":"`+code+`"}`, f.bob, 200)

	// 只有房主能切换控制权
	f.request("POST", "/api/watch/rooms/control",
		`{"code":"`+code+`","mode":"host"}`, f.bob, 403)
	toggled := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/control",
		`{"code":"`+code+`","mode":"host"}`, f.alice, 200))
	if toggled.ControlMode != "host" {
		t.Fatalf("control_mode should be host after toggle: %+v", toggled)
	}
	// 切回仅房主后，成员推送被拒
	f.request("POST", "/api/watch/rooms/state",
		`{"code":"`+code+`","playing":false,"position_ms":0}`, f.bob, 403)

	// 非法模式
	f.request("POST", "/api/watch/rooms/control",
		`{"code":"`+code+`","mode":"everyone"}`, f.alice, 400)
	f.request("POST", "/api/watch/rooms", `{"video_id":`+itoa(videoID)+`,"control_mode":"everyone"}`, f.alice, 400)

	// 默认建房是仅房主模式
	def := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms",
		`{"video_id":`+itoa(videoID)+`}`, f.alice, 200))
	if def.ControlMode != "host" {
		t.Fatalf("default control_mode should be host: %+v", def)
	}
}

func TestWatchHostStaleTransfer(t *testing.T) {
	f := newContentFixture(t)
	videoID := saveWatchVideo(t, f)
	created := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms",
		`{"video_id":`+itoa(videoID)+`}`, f.alice, 200))
	f.request("POST", "/api/watch/rooms/join", `{"code":"`+created.Code+`"}`, f.bob, 200)

	room, err := f.s.GetWatchRoomByCode(context.Background(), created.Code)
	if err != nil {
		t.Fatal(err)
	}
	// 房主在线：不转让
	hostID, err := f.s.EnsureWatchHost(context.Background(), room.ID, watchHostStale)
	if err != nil || hostID != f.alice.ID {
		t.Fatalf("host should stay: %d %v", hostID, err)
	}

	// 缩短失联阈值，模拟房主掉线：bob 心跳时房主应自动转让给他
	oldStale := watchHostStale
	watchHostStale = 30 * time.Millisecond
	defer func() { watchHostStale = oldStale }()
	time.Sleep(120 * time.Millisecond)
	beat := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/heartbeat",
		`{"code":"`+created.Code+`","position_ms":0,"since_msg_id":0}`, f.bob, 200))
	if !beat.ViewerIsHost {
		t.Fatalf("bob should become host after alice went stale: %+v", beat)
	}
	room, err = f.s.GetWatchRoomByCode(context.Background(), created.Code)
	if err != nil || room.HostID != f.bob.ID {
		t.Fatalf("room host not persisted: %+v %v", room, err)
	}

	// 过期清理：成员全部失联后房间被回收
	if _, err = f.s.CleanStaleWatchRooms(context.Background(), 0); err != nil {
		t.Fatal(err)
	}
	if _, err = f.s.GetWatchRoomByCode(context.Background(), created.Code); err != store.ErrWatchRoomNotFound {
		t.Fatalf("stale room should be cleaned, got %v", err)
	}
}

// itoa 避免在测试里同时引入 strconv 与 fmt。
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

// TestWatchHostProgressReport 房主心跳上报真实进度：与推算目标偏差大时刷新锚点
// 并广播，但不升版本（成员按漂移跟随，不触发全量对齐）；偏差在容差内则不动。
func TestWatchHostProgressReport(t *testing.T) {
	f := newContentFixture(t)
	videoID := saveWatchVideo(t, f)
	created := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms",
		`{"video_id":`+itoa(videoID)+`}`, f.alice, 200))
	code := created.Code
	f.request("POST", "/api/watch/rooms/join", `{"code":"`+code+`"}`, f.bob, 200)

	pushed := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/state",
		`{"code":"`+code+`","playing":true,"position_ms":60000}`, f.alice, 200))

	// 房主实际卡在 60s 附近（与推算目标偏差小于 1.2s）：心跳不应改动房间状态
	beat := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/heartbeat",
		`{"code":"`+code+`","position_ms":60100,"since_msg_id":0}`, f.alice, 200))
	if beat.Version != pushed.Version {
		t.Fatalf("in-tolerance heartbeat should not bump version: %+v", beat)
	}

	// 房主实际进度大幅落后（缓冲/未上报的 seek）：心跳刷新锚点，版本不变
	time.Sleep(10 * time.Millisecond)
	beat = decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/heartbeat",
		`{"code":"`+code+`","position_ms":60500,"since_msg_id":0}`, f.alice, 200))
	// 推算目标已前进约 10ms+，60500 与之偏差仍小于 1.2s —— 仍不动
	if beat.Version != pushed.Version {
		t.Fatalf("in-tolerance heartbeat should not bump version: %+v", beat)
	}

	// 成员视角：房主真实位置大幅偏离（模拟成员冲前 30 秒后房主纠偏）
	beat = decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/heartbeat",
		`{"code":"`+code+`","position_ms":90000,"since_msg_id":0}`, f.alice, 200))
	if beat.Version != pushed.Version {
		t.Fatalf("progress report must not bump version: %+v", beat)
	}
	if beat.TargetPositionMs < 89000 || beat.TargetPositionMs > 91000 {
		t.Fatalf("target should track host's real position ~90000, got %d", beat.TargetPositionMs)
	}

	// 成员心跳读到刷新后的目标，且自身不改变房间状态
	guest := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms/heartbeat",
		`{"code":"`+code+`","position_ms":90000,"since_msg_id":0}`, f.bob, 200))
	if guest.TargetPositionMs < 89000 {
		t.Fatalf("guest should see host-anchored target, got %d", guest.TargetPositionMs)
	}
	if guest.ViewerIsHost {
		t.Fatalf("guest should not be host")
	}
}

// TestWatchEventsStream 验证 SSE 推送：初始快照、状态变更、聊天与解散事件。
func TestWatchEventsStream(t *testing.T) {
	f := newContentFixture(t)
	videoID := saveWatchVideo(t, f)
	created := decodeContentData[watchSnapshot](t, f.request("POST", "/api/watch/rooms",
		`{"video_id":`+itoa(videoID)+`}`, f.alice, 200))
	code := created.Code

	server := &http.Server{Handler: f.mux}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go func() { _ = server.Serve(ln) }()
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
	}()

	req, err := http.NewRequestWithContext(context.Background(), "GET",
		"http://"+ln.Addr().String()+"/api/watch/rooms/events?code="+code+"&token="+f.tokens[f.bob.ID], nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Accept", "text/event-stream")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		t.Fatalf("content type = %q", ct)
	}

	lines := make(chan string, 64)
	go func() {
		scanner := bufio.NewScanner(resp.Body)
		for scanner.Scan() {
			lines <- scanner.Text()
		}
		close(lines)
	}()

	readEvent := func(wantEvent string, timeout time.Duration) (string, bool) {
		deadline := time.After(timeout)
		eventName := ""
		for {
			select {
			case line, ok := <-lines:
				if !ok {
					return "", false
				}
				if strings.HasPrefix(line, "event: ") {
					eventName = strings.TrimPrefix(line, "event: ")
				}
				if strings.HasPrefix(line, "data: ") && eventName == wantEvent {
					return strings.TrimPrefix(line, "data: "), true
				}
			case <-deadline:
				return "", false
			}
		}
	}

	// 初始快照
	data, ok := readEvent("state", 5*time.Second)
	if !ok || !strings.Contains(data, `"code":"`+code+`"`) {
		t.Fatalf("initial state event missing: %q", data)
	}

	// 房主推送状态 → 订阅者即时收到
	f.request("POST", "/api/watch/rooms/state",
		`{"code":"`+code+`","playing":true,"position_ms":90000}`, f.alice, 200)
	data, ok = readEvent("state", 5*time.Second)
	if !ok || !strings.Contains(data, `"playing":true`) {
		t.Fatalf("state push not received: %q", data)
	}

	// 聊天 → chat 事件
	f.request("POST", "/api/watch/rooms/chat",
		`{"code":"`+code+`","content":"SSE测试"}`, f.alice, 200)
	data, ok = readEvent("chat", 5*time.Second)
	if !ok || !strings.Contains(data, "SSE测试") {
		t.Fatalf("chat event not received: %q", data)
	}

	// 解散：所有成员都退出后房间删除 → closed 事件（SSE 端点会自动补挂 bob，先让他退出）
	f.request("POST", "/api/watch/rooms/leave", `{"code":"`+code+`"}`, f.bob, 200)
	f.request("POST", "/api/watch/rooms/leave", `{"code":"`+code+`"}`, f.alice, 200)
	if data, ok = readEvent("closed", 5*time.Second); !ok {
		t.Fatalf("closed event not received")
	}
}
