package scheduler

import (
	"context"
	"fmt"
	"sync"
	"time"

	"video-collection-api/config"
	"video-collection-api/pkg/ingest"
	"video-collection-api/pkg/maccms"
	"video-collection-api/pkg/store"
)

// LogItem 采集运行实时日志
type LogItem struct {
	ID         int64     `json:"id"`
	Time       time.Time `json:"time"`
	SourceID   string    `json:"source_id"`
	SourceName string    `json:"source_name"`
	Level      string    `json:"level"` // INFO, WARN, SUCCESS, ERROR
	Message    string    `json:"message"`
}

// TaskProgress 采集任务状态与进度
type TaskProgress struct {
	SourceID     string    `json:"source_id"`
	SourceName   string    `json:"source_name"`
	IsRunning    bool      `json:"is_running"`
	CurrentPage  int       `json:"current_page"`
	TotalPages   int       `json:"total_pages"`
	TotalFetched int       `json:"total_fetched"`
	TotalSaved   int       `json:"total_saved"`
	TotalSkipped int       `json:"total_skipped"`
	StartTime    time.Time `json:"start_time"`
	LastError    string    `json:"last_error,omitempty"`
}

// AutoCollectStatus 定时自动采集配置与状态
type AutoCollectStatus struct {
	Enabled       bool      `json:"enabled"`
	IntervalHours int       `json:"interval_hours"`
	LastRun       time.Time `json:"last_run"`
	NextRun       time.Time `json:"next_run"`
}

// Scheduler 采集任务调度中心
type Scheduler struct {
	store             store.Store
	mu                sync.RWMutex
	progress          map[string]*TaskProgress
	logs              []LogItem
	logIDSeq          int64
	maxLogs           int
	autoEnabled       bool
	autoIntervalHours int
	lastAutoRun       time.Time
	nextAutoRun       time.Time
}

// NewScheduler 创建调度器并启动自动轮询工作线程
func NewScheduler(s store.Store) *Scheduler {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	enabledStr, _ := s.GetSetting(ctx, "auto_collect_enabled", "0")
	intervalStr, _ := s.GetSetting(ctx, "auto_collect_interval_hours", "2")
	intervalH := 2
	if h, err := time.ParseDuration(intervalStr + "h"); err == nil && h >= time.Hour {
		intervalH = int(h.Hours())
	}

	sc := &Scheduler{
		store:             s,
		progress:          make(map[string]*TaskProgress),
		logs:              make([]LogItem, 0, 500),
		maxLogs:           500,
		autoEnabled:       enabledStr == "1",
		autoIntervalHours: intervalH,
	}

	if sc.autoEnabled {
		sc.nextAutoRun = time.Now().Add(time.Duration(sc.autoIntervalHours) * time.Hour)
	}

	go sc.startAutoCollectWorker()

	return sc
}

func (sc *Scheduler) startAutoCollectWorker() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		sc.mu.RLock()
		enabled := sc.autoEnabled
		intervalH := sc.autoIntervalHours
		nextRun := sc.nextAutoRun
		sc.mu.RUnlock()

		if !enabled {
			continue
		}

		now := time.Now()
		if nextRun.IsZero() {
			sc.mu.Lock()
			sc.nextAutoRun = now.Add(time.Duration(intervalH) * time.Hour)
			sc.mu.Unlock()
			continue
		}

		if now.After(nextRun) {
			sc.mu.Lock()
			sc.lastAutoRun = now
			sc.nextAutoRun = now.Add(time.Duration(intervalH) * time.Hour)
			nextRun = sc.nextAutoRun
			sc.mu.Unlock()

			sc.AddLog("system", "系统定时计划", "INFO", fmt.Sprintf("自动定时轮询触发：正在执行全网采集源按各源配置采集 (下次执行: %s)",
				nextRun.Format("15:04:05")))
			_ = sc.TriggerCollectAll(-1)
		}
	}
}

// GetAutoCollectStatus 获取定时采集状态
func (sc *Scheduler) GetAutoCollectStatus() AutoCollectStatus {
	sc.mu.RLock()
	defer sc.mu.RUnlock()
	return AutoCollectStatus{
		Enabled:       sc.autoEnabled,
		IntervalHours: sc.autoIntervalHours,
		LastRun:       sc.lastAutoRun,
		NextRun:       sc.nextAutoRun,
	}
}

// SetAutoCollectConfig 更新定时采集配置
func (sc *Scheduler) SetAutoCollectConfig(ctx context.Context, enabled bool, intervalHours int) error {
	if intervalHours <= 0 {
		intervalHours = 2
	}

	sc.mu.Lock()
	sc.autoEnabled = enabled
	sc.autoIntervalHours = intervalHours
	if enabled {
		sc.nextAutoRun = time.Now().Add(time.Duration(intervalHours) * time.Hour)
	} else {
		sc.nextAutoRun = time.Time{}
	}
	sc.mu.Unlock()

	enabledVal := "0"
	if enabled {
		enabledVal = "1"
	}
	_ = sc.store.SetSetting(ctx, "auto_collect_enabled", enabledVal)
	_ = sc.store.SetSetting(ctx, "auto_collect_interval_hours", fmt.Sprintf("%d", intervalHours))

	statusStr := "禁用"
	if enabled {
		statusStr = fmt.Sprintf("开启 (每 %d 小时自动运行)", intervalHours)
	}
	sc.AddLog("system", "系统设置", "SUCCESS", "自动定时采集计划已更新: "+statusStr)
	return nil
}

// TriggerCollectAll 触发所有已启用的采集点执行采集
func (sc *Scheduler) TriggerCollectAll(customHours int) error {
	ctx := context.Background()
	sources, err := sc.store.GetSources(ctx)
	if err != nil {
		return err
	}

	triggered := 0
	for _, src := range sources {
		if src.Enabled {
			if err := sc.TriggerCollect(src.ID, customHours); err == nil {
				triggered++
			}
		}
	}

	sc.AddLog("system", "全局采集", "INFO", fmt.Sprintf("已成功为 %d 个启用状态的采集点启动采集流水线", triggered))
	return nil
}

// AddLog 记录采集日志
func (sc *Scheduler) AddLog(sourceID, sourceName, level, msg string) {
	sc.mu.Lock()
	defer sc.mu.Unlock()

	sc.logIDSeq++
	item := LogItem{
		ID:         sc.logIDSeq,
		Time:       time.Now(),
		SourceID:   sourceID,
		SourceName: sourceName,
		Level:      level,
		Message:    msg,
	}

	if len(sc.logs) >= sc.maxLogs {
		sc.logs = sc.logs[1:]
	}
	sc.logs = append(sc.logs, item)
}

// GetRecentLogs 获取最近的采集日志
func (sc *Scheduler) GetRecentLogs(limit int) []LogItem {
	sc.mu.RLock()
	defer sc.mu.RUnlock()

	if limit <= 0 || limit > len(sc.logs) {
		limit = len(sc.logs)
	}

	start := len(sc.logs) - limit
	result := make([]LogItem, limit)
	copy(result, sc.logs[start:])
	return result
}

// GetProgressList 获取所有源的运行状态与进度
func (sc *Scheduler) GetProgressList() map[string]TaskProgress {
	sc.mu.RLock()
	defer sc.mu.RUnlock()

	res := make(map[string]TaskProgress)
	for k, v := range sc.progress {
		res[k] = *v
	}
	return res
}

// TriggerCollect 触发单个采集源的即时采集任务 (异步执行)
func (sc *Scheduler) TriggerCollect(sourceID string, customHours int) error {
	ctx := context.Background()
	src, err := sc.store.GetSourceByID(ctx, sourceID)
	if err != nil {
		return err
	}
	if src == nil {
		return fmt.Errorf("source id %s not found", sourceID)
	}
	if src.Type == "pipeline" {
		if err := ingest.Validate(*src); err != nil {
			return err
		}
	} else if err := config.ValidateCollectionSource(*src); err != nil {
		return err
	}

	sc.mu.Lock()
	prog, exists := sc.progress[sourceID]
	if exists && prog.IsRunning {
		sc.mu.Unlock()
		return fmt.Errorf("采集源 [%s] 正在采集中，请勿重复触发", src.Name)
	}

	prog = &TaskProgress{
		SourceID:   sourceID,
		SourceName: src.Name,
		IsRunning:  true,
		StartTime:  time.Now(),
	}
	sc.progress[sourceID] = prog
	sc.mu.Unlock()

	// 异步启动采集
	go sc.runCollectTask(context.Background(), *src, customHours, prog)
	return nil
}

// runCollectTask 执行具体的采集任务流水线
func (sc *Scheduler) runCollectTask(ctx context.Context, src config.SourceConfig, customHours int, prog *TaskProgress) {
	defer func() {
		sc.mu.Lock()
		prog.IsRunning = false
		sc.mu.Unlock()
	}()

	if src.Type == "pipeline" {
		sc.runPipeline(ctx, src, prog)
		return
	}
	client := maccms.NewClient(src)
	isAll := customHours == 0 || (customHours < 0 && src.CollectHours == 0)
	hours := src.CollectHours
	if customHours >= 0 {
		hours = customHours
	}

	modeDesc := fmt.Sprintf("近 %d 小时增量采集（按规则构造请求参数）", hours)
	if isAll {
		modeDesc = "全量采集（省略增量参数，遵守页数上限）"
	}
	sc.AddLog(src.ID, src.Name, "INFO", fmt.Sprintf("开始执行采集任务: %s", modeDesc))

	page := 1
	maxPages := src.PageLimit
	// Legacy zero means no configured page limit; full runs respect positive limits.
	if maxPages <= 0 {
		maxPages = 999999
	}

	interval := time.Duration(src.IntervalMs) * time.Millisecond

	for page <= maxPages {
		select {
		case <-ctx.Done():
			sc.AddLog(src.ID, src.Name, "WARN", "采集任务被外部取消")
			return
		default:
		}

		qParams := maccms.QueryParams{
			Action: "detail",
			Page:   page,
			Hours:  hours,
			IsAll:  isAll,
		}

		sc.AddLog(src.ID, src.Name, "INFO", fmt.Sprintf("正在拉取第 %d 页", page))

		cleanedList, rawResp, err := client.CollectPage(ctx, qParams)
		if err != nil {
			sc.mu.Lock()
			prog.LastError = err.Error()
			sc.mu.Unlock()
			sc.AddLog(src.ID, src.Name, "ERROR", fmt.Sprintf("拉取第 %d 页数据失败: %v", page, err))
			return
		}

		totalPageCount := rawResp.PageCount.Int()
		if totalPageCount == 0 && len(rawResp.List) > 0 {
			totalPageCount = page
		}

		sc.mu.Lock()
		prog.CurrentPage = page
		prog.TotalPages = totalPageCount
		prog.TotalFetched += len(rawResp.List)
		sc.mu.Unlock()

		if len(rawResp.List) == 0 {
			sc.AddLog(src.ID, src.Name, "INFO", fmt.Sprintf("第 %d 页无数据，采集流程结束", page))
			break
		}

		skippedThisPage := len(rawResp.List) - len(cleanedList)
		savedThisPage := 0

		// 入库保存
		for _, cleaned := range cleanedList {
			if cleaned.SourceID == "" {
				cleaned.SourceID = src.ID
			}
			if cleaned.SourceName == "" {
				cleaned.SourceName = src.Name
			}
			vid, err := sc.store.UpsertVideo(ctx, src.ID, &cleaned)
			if err != nil {
				sc.AddLog(src.ID, src.Name, "WARN", fmt.Sprintf("入库失败 [%s]: %v", cleaned.Name, err))
			} else {
				savedThisPage++
				sc.AddLog(src.ID, src.Name, "SUCCESS", fmt.Sprintf("入库成功 [ID:%d]: %s (播放源:%d个, 分类:%s)",
					vid, cleaned.Name, len(cleaned.PlayGroups), cleaned.TargetTypeName))
			}
		}

		sc.mu.Lock()
		prog.TotalSaved += savedThisPage
		prog.TotalSkipped += skippedThisPage
		sc.mu.Unlock()

		sc.AddLog(src.ID, src.Name, "INFO", fmt.Sprintf("第 %d/%d 页处理完成: 抓取 %d 条, 入库 %d 条, 规则过滤 %d 条",
			page, totalPageCount, len(rawResp.List), savedThisPage, skippedThisPage))

		if page >= totalPageCount {
			sc.AddLog(src.ID, src.Name, "SUCCESS", "已到达最后一页，本次采集圆满完成")
			break
		}

		page++
		if interval > 0 {
			timer := time.NewTimer(interval)
			select {
			case <-ctx.Done():
				timer.Stop()
				return
			case <-timer.C:
			}
		}
	}

	sc.AddLog(src.ID, src.Name, "SUCCESS", fmt.Sprintf("采集汇总: 总抓取 %d 条，有效入库 %d 条，过滤 %d 条，用时 %s",
		prog.TotalFetched, prog.TotalSaved, prog.TotalSkipped, time.Since(prog.StartTime).Round(time.Second)))
}
