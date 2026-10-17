package store

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

func TestCollectionTaskAndLogs(t *testing.T) {
	tmpDir := t.TempDir()
	dbPath := filepath.Join(tmpDir, "test_tasks.db")
	s, err := NewSQLiteStore(dbPath)
	if err != nil {
		t.Fatalf("failed to init store: %v", err)
	}
	defer s.Close()

	ctx := context.Background()

	// 1. 创建任务
	task := &CollectionTask{
		SourceID:     "maccms_main",
		SourceName:   "主影视采集节点",
		TriggerType:  "manual",
		CollectHours: 24,
		Status:       "running",
	}
	taskID, err := s.CreateCollectionTask(ctx, task)
	if err != nil {
		t.Fatalf("CreateCollectionTask error: %v", err)
	}
	if taskID <= 0 {
		t.Fatalf("expected positive taskID, got %d", taskID)
	}

	// 2. 更新进度
	err = s.UpdateCollectionTaskProgress(ctx, taskID, 50, 45, 5)
	if err != nil {
		t.Fatalf("UpdateCollectionTaskProgress error: %v", err)
	}

	fetchedTask, err := s.GetCollectionTask(ctx, taskID)
	if err != nil || fetchedTask == nil {
		t.Fatalf("GetCollectionTask error: %v", err)
	}
	if fetchedTask.TotalFetched != 50 || fetchedTask.TotalSaved != 45 || fetchedTask.TotalSkipped != 5 {
		t.Errorf("unexpected counts: %+v", fetchedTask)
	}
	if fetchedTask.Status != "running" {
		t.Errorf("expected running status, got %s", fetchedTask.Status)
	}

	// 3. 记录日志
	err = s.AddCollectionLog(ctx, CollectionLog{
		TaskID:     taskID,
		SourceID:   "maccms_main",
		SourceName: "主影视采集节点",
		Level:      "INFO",
		Message:    "开始拉取第一页数据",
	})
	if err != nil {
		t.Fatalf("AddCollectionLog error: %v", err)
	}

	batchLogs := []CollectionLog{
		{
			TaskID:     taskID,
			SourceID:   "maccms_main",
			SourceName: "主影视采集节点",
			Level:      "SUCCESS",
			Message:    "入库成功: 假面骑士极狐",
		},
		{
			TaskID:     taskID,
			SourceID:   "maccms_main",
			SourceName: "主影视采集节点",
			Level:      "WARN",
			Message:    "已跳过重复数据: 奥特曼",
		},
	}
	err = s.BatchAddCollectionLogs(ctx, batchLogs)
	if err != nil {
		t.Fatalf("BatchAddCollectionLogs error: %v", err)
	}

	// 4. 查询任务日志
	logs, totalLogs, err := s.ListCollectionLogs(ctx, CollectionLogQuery{
		TaskID: taskID,
	})
	if err != nil {
		t.Fatalf("ListCollectionLogs error: %v", err)
	}
	if totalLogs != 3 || len(logs) != 3 {
		t.Errorf("expected 3 logs, got total %d, returned %d", totalLogs, len(logs))
	}
	// 验证顺序为时间升序
	if logs[0].Level != "INFO" || logs[1].Level != "SUCCESS" || logs[2].Level != "WARN" {
		t.Errorf("unexpected log sequence: %+v", logs)
	}

	// 5. 完成任务
	err = s.FinishCollectionTask(ctx, taskID, "success", "", 100, 92, 8)
	if err != nil {
		t.Fatalf("FinishCollectionTask error: %v", err)
	}

	finishedTask, err := s.GetCollectionTask(ctx, taskID)
	if err != nil || finishedTask == nil {
		t.Fatalf("GetCollectionTask after finish error: %v", err)
	}
	if finishedTask.Status != "success" {
		t.Errorf("expected success status, got %s", finishedTask.Status)
	}
	if finishedTask.EndedAt == nil {
		t.Errorf("expected EndedAt to be set")
	}
	if finishedTask.TotalSaved != 92 {
		t.Errorf("expected TotalSaved 92, got %d", finishedTask.TotalSaved)
	}

	// 6. 分页查询任务列表
	tasks, totalTasks, err := s.ListCollectionTasks(ctx, CollectionTaskQuery{
		SourceID: "maccms_main",
	})
	if err != nil {
		t.Fatalf("ListCollectionTasks error: %v", err)
	}
	if totalTasks < 1 || len(tasks) < 1 {
		t.Errorf("expected at least 1 task, got %d", totalTasks)
	}

	// 7. 日志清理测试
	deleted, err := s.ClearCollectionLogs(ctx, 0)
	if err != nil {
		t.Fatalf("ClearCollectionLogs error: %v", err)
	}
	// 刚刚生成的日志时间为当前时间，15天内不应被删除
	if deleted > 0 {
		t.Errorf("expected 0 deleted recent logs, got %d", deleted)
	}
	_ = time.Second
}
