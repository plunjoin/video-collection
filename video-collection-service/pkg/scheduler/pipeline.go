package scheduler

import (
	"context"
	"fmt"
	"strings"
	"time"

	"video-collection-service/config"
	"video-collection-service/pkg/ingest"
	"video-collection-service/pkg/store"
)

func (sc *Scheduler) runPipeline(ctx context.Context, src config.SourceConfig, prog *TaskProgress) {
	p := src.Filter.Pipeline
	sc.AddTaskLog(prog.TaskID, src.ID, src.Name, "INFO", fmt.Sprintf("Bllii-Familiar 启动使魔通用规则采集 (任务批次 #%d)：读取 → 提取 → 清洗 → 校验 → 入库（按唯一字段去重）", prog.TaskID))

	defer func() {
		sc.mu.Lock()
		prog.IsRunning = false
		lastErr := prog.LastError
		fetched := prog.TotalFetched
		saved := prog.TotalSaved
		skipped := prog.TotalSkipped
		sc.mu.Unlock()

		finalStatus := "success"
		if lastErr != "" {
			finalStatus = "failed"
		}
		if prog.TaskID > 0 {
			_ = sc.store.FinishCollectionTask(context.Background(), prog.TaskID, finalStatus, lastErr, fetched, saved, skipped)
		}
	}()

	processedCount := 0
	err := ingest.Run(ctx, src, 0, func(sample ingest.Sample) error {
		sc.mu.Lock()
		prog.TotalFetched++
		sc.mu.Unlock()
		if len(sample.Errors) > 0 {
			sc.mu.Lock()
			prog.TotalSkipped++
			sc.mu.Unlock()
			sc.AddTaskLog(prog.TaskID, src.ID, src.Name, "WARN", strings.Join(sample.Errors, "；"))
			return nil
		}
		v := sample.Values
		r := store.CollectionRecord{SourceID: src.ID, Target: p.Target, Key: v[p.KeyField], Values: v}

		saved, err := store.WriteBusinessRecord(ctx, sc.store, r, p.Duplicate == "skip", src.Name)
		if err != nil {
			return err
		}
		sc.mu.Lock()
		if saved {
			prog.TotalSaved++
		} else {
			prog.TotalSkipped++
		}
		fetchedNow := prog.TotalFetched
		savedNow := prog.TotalSaved
		skippedNow := prog.TotalSkipped
		sc.mu.Unlock()

		processedCount++
		if processedCount%10 == 0 && prog.TaskID > 0 {
			_ = sc.store.UpdateCollectionTaskProgress(ctx, prog.TaskID, fetchedNow, savedNow, skippedNow)
		}

		return nil
	}, ingest.RegistryLookup(ctx, sc.store))
	if err != nil {
		sc.mu.Lock()
		prog.LastError = err.Error()
		sc.mu.Unlock()
		sc.AddTaskLog(prog.TaskID, src.ID, src.Name, "ERROR", fmt.Sprintf("采集停止：%v；已入库记录保留，可修正配置后重新运行", err))
		return
	}
	sc.AddTaskLog(prog.TaskID, src.ID, src.Name, "SUCCESS", fmt.Sprintf("采集完成：读取 %d 条，保存 %d 条，跳过 %d 条，用时 %s", prog.TotalFetched, prog.TotalSaved, prog.TotalSkipped, time.Since(prog.StartTime).Round(time.Second)))
}
