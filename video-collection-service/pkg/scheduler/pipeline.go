package scheduler

import (
	"context"
	"fmt"
	"strings"
	"time"

	"video-collection-service/config"
	"video-collection-service/pkg/collector"
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
		if p.Target == "video" {
			if p.Duplicate == "skip" {
				exists, err := sc.store.HasCollectionRecord(ctx, src.ID, p.Target, r.Key)
				if err != nil {
					return err
				}
				if exists {
					sc.mu.Lock()
					prog.TotalSkipped++
					sc.mu.Unlock()
					return nil
				}
			}
			vod := collector.CleanedVod{
				SourceID:       src.ID,
				SourceName:     src.Name,
				Name:           v["title"],
				SubName:        v["sub_name"],
				Content:        v["content"],
				Picture:        v["cover"],
				TargetTypeName: v["category"],
				Year:           v["year"],
				Actor:          v["actor"],
				Director:       v["director"],
				Area:           v["area"],
				Remarks:        v["remarks"],
			}
			vod.SourceTypeName = v["category"]
			playURL := v["play_url"]
			if playURL != "" {
				playFrom := v["play_from"]
				if playFrom == "" {
					playFrom = "m3u8"
				}
				groups := collector.ParsePlayGroups(playFrom, v["play_server"], v["play_note"], playURL)
				for i := range groups {
					if groups[i].SourceID == "" {
						groups[i].SourceID = src.ID
					}
					if groups[i].SourceName == "" {
						groups[i].SourceName = src.Name
					}
				}
				vod.PlayGroups = groups
			}
			id, err := sc.store.UpsertVideo(ctx, src.ID, &vod)
			if err != nil {
				return err
			}
			r.ContentID = id
		}
		saved, err := sc.store.SaveCollectionRecord(ctx, r, p.Duplicate == "skip")
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
	})
	if err != nil {
		sc.mu.Lock()
		prog.LastError = err.Error()
		sc.mu.Unlock()
		sc.AddTaskLog(prog.TaskID, src.ID, src.Name, "ERROR", fmt.Sprintf("采集停止：%v；已入库记录保留，可修正配置后重新运行", err))
		return
	}
	sc.AddTaskLog(prog.TaskID, src.ID, src.Name, "SUCCESS", fmt.Sprintf("采集完成：读取 %d 条，保存 %d 条，跳过 %d 条，用时 %s", prog.TotalFetched, prog.TotalSaved, prog.TotalSkipped, time.Since(prog.StartTime).Round(time.Second)))
}
