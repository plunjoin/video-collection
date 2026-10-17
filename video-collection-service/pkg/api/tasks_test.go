package api

import (
	"context"
	"fmt"
	"testing"
	"time"

	"video-collection-service/pkg/store"
)

func TestCollectionTasksAndLogsAPI(t *testing.T) {
	f := newContentFixture(t)
	ctx := context.Background()

	// 1. 权限拦截测试
	f.request("GET", "/api/admin/collection/tasks", "", nil, 401)
	f.request("GET", "/api/admin/collection/tasks", "", f.alice, 401)
	f.request("GET", "/api/admin/collection/logs", "", nil, 401)
	f.request("GET", "/api/admin/collection/logs", "", f.alice, 401)
	f.request("POST", "/api/admin/collection/logs/cleanup", `{"days":15}`, f.alice, 401)

	// 2. 模拟创建一个任务记录
	task := &store.CollectionTask{
		SourceID:     "test_src_1",
		SourceName:   "影视测试节点",
		TriggerType:  "manual",
		CollectHours: 24,
		Status:       "running",
	}
	taskID, err := f.s.CreateCollectionTask(ctx, task)
	if err != nil {
		t.Fatalf("CreateCollectionTask error: %v", err)
	}

	// 记录两条日志
	_ = f.s.AddCollectionLog(ctx, store.CollectionLog{
		TaskID:     taskID,
		SourceID:   "test_src_1",
		SourceName: "影视测试节点",
		Level:      "INFO",
		Message:    "任务已创建并开始拉取数据",
		CreatedAt:  time.Now().UTC(),
	})
	_ = f.s.AddCollectionLog(ctx, store.CollectionLog{
		TaskID:     taskID,
		SourceID:   "test_src_1",
		SourceName: "影视测试节点",
		Level:      "SUCCESS",
		Message:    "第 1 页抓取完成，成功入库 20 条",
		CreatedAt:  time.Now().UTC(),
	})

	// 3. GET /api/admin/collection/tasks
	tasksResp := f.request("GET", "/api/admin/collection/tasks?source_id=test_src_1", "", f.admin, 200)
	tasksList := decodeContentData[[]store.CollectionTask](t, tasksResp)
	if len(tasksList) == 0 {
		t.Fatalf("expected tasks, got 0")
	}
	if tasksList[0].ID != taskID || tasksList[0].SourceName != "影视测试节点" {
		t.Errorf("unexpected task data: %+v", tasksList[0])
	}

	// 4. GET /api/admin/collection/tasks/detail
	detailResp := f.request("GET", "/api/admin/collection/tasks/detail?id=99999", "", f.admin, 404)
	_ = detailResp
	detailResp = f.request("GET", fmt.Sprintf("/api/admin/collection/tasks/detail?id=%d", taskID), "", f.admin, 200)
	var detailData struct {
		Task store.CollectionTask  `json:"task"`
		Logs []store.CollectionLog `json:"logs"`
	}
	detailData = decodeContentData[struct {
		Task store.CollectionTask  `json:"task"`
		Logs []store.CollectionLog `json:"logs"`
	}](t, detailResp)
	if detailData.Task.ID != taskID {
		t.Errorf("expected task id %d, got %d", taskID, detailData.Task.ID)
	}
	if len(detailData.Logs) != 2 {
		t.Errorf("expected 2 logs in detail, got %d", len(detailData.Logs))
	}

	// 5. GET /api/admin/collection/logs
	logsResp := f.request("GET", "/api/admin/collection/logs?source_id=test_src_1&level=SUCCESS", "", f.admin, 200)
	logsList := decodeContentData[[]store.CollectionLog](t, logsResp)
	if len(logsList) != 1 || logsList[0].Level != "SUCCESS" {
		t.Errorf("unexpected filtered logs: %+v", logsList)
	}

	// 6. POST /api/admin/collection/logs/cleanup
	cleanResp := f.request("POST", "/api/admin/collection/logs/cleanup", `{"days":30}`, f.admin, 200)
	var cleanResult struct {
		Deleted int64 `json:"deleted"`
	}
	cleanResult = decodeContentData[struct {
		Deleted int64 `json:"deleted"`
	}](t, cleanResp)
	if cleanResult.Deleted != 0 {
		t.Errorf("expected 0 deleted recent logs, got %d", cleanResult.Deleted)
	}
}
