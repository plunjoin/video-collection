package scheduler

import (
	"context"
	"fmt"
	"strings"
	"time"

	"video-collection-api/config"
	"video-collection-api/pkg/ingest"
	"video-collection-api/pkg/maccms"
	"video-collection-api/pkg/store"
)

func (sc *Scheduler) runPipeline(ctx context.Context, src config.SourceConfig, prog *TaskProgress) {
	p := src.Filter.Pipeline
	sc.AddLog(src.ID, src.Name, "INFO", "开始通用采集：读取 → 提取 → 清洗 → 校验 → 入库（按唯一字段去重）")
	err := ingest.Run(ctx, src, 0, func(sample ingest.Sample) error {
		sc.mu.Lock()
		prog.TotalFetched++
		sc.mu.Unlock()
		if len(sample.Errors) > 0 {
			sc.mu.Lock()
			prog.TotalSkipped++
			sc.mu.Unlock()
			sc.AddLog(src.ID, src.Name, "WARN", strings.Join(sample.Errors, "；"))
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
			vod := maccms.CleanedVod{SourceID: src.ID, SourceName: src.Name, Name: v["title"], Content: v["content"], Picture: v["cover"], TargetTypeName: v["category"], Year: v["year"], Actor: v["actor"], Director: v["director"], Area: v["area"], Remarks: v["remarks"]}
			vod.SourceTypeName = v["category"]
			if v["play_url"] != "" {
				vod.PlayGroups = []maccms.PlayGroup{{SourceID: src.ID, SourceName: src.Name, PlayerCode: "m3u8", Episodes: []maccms.Episode{{Name: "正片", URL: v["play_url"]}}}}
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
		sc.mu.Unlock()
		return nil
	})
	if err != nil {
		sc.mu.Lock()
		prog.LastError = err.Error()
		sc.mu.Unlock()
		sc.AddLog(src.ID, src.Name, "ERROR", fmt.Sprintf("采集停止：%v；已入库记录保留，可修正配置后重新运行", err))
		return
	}
	sc.AddLog(src.ID, src.Name, "SUCCESS", fmt.Sprintf("采集完成：读取 %d 条，保存 %d 条，跳过 %d 条，用时 %s", prog.TotalFetched, prog.TotalSaved, prog.TotalSkipped, time.Since(prog.StartTime).Round(time.Second)))
}
