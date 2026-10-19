package webhook

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"video-collection-service/pkg/collector"
)

// Payload 解析后的 webhook 载荷。
type Payload struct {
	Event  string                 // 事件类型（如 video.upsert），空表示未声明
	Videos []collector.CleanedVod // 解析出的待入库视频条目
}

// 字段别名候选：标准苹果 CMS 字段（vod_xxx）优先，其次短名/驼峰兼容。
var fieldAliases = map[string][]string{
	"original_id":      {"vod_id", "original_id", "id", "vid"},
	"name":             {"vod_name", "name", "title"},
	"sub_name":         {"vod_sub", "sub_name", "subtitle"},
	"target_type_id":   {"type_id", "target_type_id", "typeid"},
	"target_type_name": {"type_name", "target_type_name", "typename"},
	"source_type_name": {"source_type_name", "source_type"},
	"picture":          {"vod_pic", "picture", "pic", "cover"},
	"actor":            {"vod_actor", "actor"},
	"director":         {"vod_director", "director"},
	"area":             {"vod_area", "area"},
	"language":         {"vod_lang", "language", "lang"},
	"year":             {"vod_year", "year"},
	"remarks":          {"vod_remarks", "remarks", "note"},
	"content":          {"vod_content", "content", "description", "blurb"},
	"update_time":      {"vod_time", "update_time", "updated_at"},
	"play_from":        {"vod_play_from", "play_from", "player_from"},
	"play_server":      {"vod_play_server", "play_server"},
	"play_note":        {"vod_play_note", "play_note"},
	"play_url":         {"vod_play_url", "play_url", "url", "playurl"},
}

// ParsePayload 解析原始 webhook 报文为结构化视频条目。
// 兼容单条对象、数组、{"data":...} 包裹与 {"list":[...]} 标准采集接口形态；
// 字段同时兼容 vod_xxx 标准键与短名。
func ParsePayload(raw []byte) (*Payload, error) {
	if len(strings.TrimSpace(string(raw))) == 0 {
		return nil, fmt.Errorf("请求体为空")
	}
	var root any
	if err := json.Unmarshal(raw, &root); err != nil {
		return nil, fmt.Errorf("请求体不是合法 JSON: %w", err)
	}
	p := &Payload{}
	switch v := root.(type) {
	case []any:
		items, err := collectVods(v)
		if err != nil {
			return nil, err
		}
		p.Videos = items
	case map[string]any:
		p.Event = pickEvent(v)
		// {"data": {...} | [...] | {"list": [...]}}
		if data, ok := v["data"]; ok && data != nil {
			items, err := collectData(data)
			if err != nil {
				return nil, err
			}
			p.Videos = items
			break
		}
		// {"list": [...]} 标准采集接口形态
		if list, ok := v["list"].([]any); ok {
			items, err := collectVods(list)
			if err != nil {
				return nil, err
			}
			p.Videos = items
			break
		}
		// 单条视频对象
		items, err := collectVods([]any{v})
		if err != nil {
			return nil, err
		}
		p.Videos = items
	default:
		return nil, fmt.Errorf("请求体顶层必须是 JSON 对象或数组")
	}
	if len(p.Videos) == 0 {
		return nil, fmt.Errorf("未解析到任何视频条目")
	}
	return p, nil
}

// collectData 解析 data 字段：支持 {"list":[...]} 包裹、单条对象与数组三种形态。
func collectData(data any) ([]collector.CleanedVod, error) {
	switch d := data.(type) {
	case map[string]any:
		if list, ok := d["list"].([]any); ok {
			return collectVods(list)
		}
		return collectVods([]any{d})
	case []any:
		return collectVods(d)
	default:
		return nil, fmt.Errorf("data 字段类型不支持")
	}
}

func pickEvent(m map[string]any) string {
	for _, k := range []string{"event", "type", "event_type", "action"} {
		if s, ok := m[k].(string); ok && strings.TrimSpace(s) != "" {
			return strings.TrimSpace(s)
		}
	}
	return ""
}

func collectVods(items []any) ([]collector.CleanedVod, error) {
	var out []collector.CleanedVod
	for _, item := range items {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		vod, err := vodFromMap(m)
		if err != nil {
			return nil, err
		}
		if strings.TrimSpace(vod.Name) == "" && len(vod.PlayGroups) == 0 {
			continue
		}
		out = append(out, vod)
	}
	return out, nil
}

// vodFromMap 将一条 JSON 对象映射为 CleanedVod；播放线路字符串由 ParsePlayGroups 解析。
func vodFromMap(m map[string]any) (collector.CleanedVod, error) {
	lower := make(map[string]any, len(m))
	for k, v := range m {
		lower[strings.ToLower(strings.TrimSpace(k))] = v
	}
	lookup := func(field string) any {
		for _, alias := range fieldAliases[field] {
			if v, ok := lower[alias]; ok && v != nil {
				return v
			}
		}
		return nil
	}
	vod := collector.CleanedVod{
		OriginalID:     toInt(lookup("original_id")),
		Name:           toStr(lookup("name")),
		SubName:        toStr(lookup("sub_name")),
		TargetTypeID:   toInt(lookup("target_type_id")),
		TargetTypeName: toStr(lookup("target_type_name")),
		SourceTypeName: toStr(lookup("source_type_name")),
		Picture:        toStr(lookup("picture")),
		Actor:          toStr(lookup("actor")),
		Director:       toStr(lookup("director")),
		Area:           toStr(lookup("area")),
		Language:       toStr(lookup("language")),
		Year:           toStr(lookup("year")),
		Remarks:        toStr(lookup("remarks")),
		Content:        toStr(lookup("content")),
		UpdateTime:     toStr(lookup("update_time")),
	}
	vod.PlayGroups = collector.ParsePlayGroups(
		toStr(lookup("play_from")), toStr(lookup("play_server")), toStr(lookup("play_note")), toStr(lookup("play_url")))
	return vod, nil
}

// AttachSource 为播放线路补全来源标识（webhook 未显式提供时）。
func AttachSource(vods []collector.CleanedVod, sourceID, sourceName string) {
	for i := range vods {
		for j := range vods[i].PlayGroups {
			if vods[i].PlayGroups[j].SourceID == "" {
				vods[i].PlayGroups[j].SourceID = sourceID
			}
			if vods[i].PlayGroups[j].SourceName == "" && sourceName != "" {
				vods[i].PlayGroups[j].SourceName = sourceName
			}
		}
	}
}

// ToRecords 将视频条目转换为通用采集记录（target=record 时使用）。
func ToRecords(p *Payload) []map[string]string {
	records := make([]map[string]string, 0, len(p.Videos))
	for _, v := range p.Videos {
		records = append(records, map[string]string{
			"title":    v.Name,
			"sub_name": v.SubName,
			"picture":  v.Picture,
			"actor":    v.Actor,
			"director": v.Director,
			"area":     v.Area,
			"language": v.Language,
			"year":     v.Year,
			"remarks":  v.Remarks,
			"content":  v.Content,
		})
	}
	return records
}

func toStr(v any) string {
	switch t := v.(type) {
	case string:
		return strings.TrimSpace(t)
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	case bool:
		return strconv.FormatBool(t)
	case nil:
		return ""
	default:
		return strings.TrimSpace(fmt.Sprint(t))
	}
}

func toInt(v any) int {
	switch t := v.(type) {
	case float64:
		return int(t)
	case string:
		n, _ := strconv.Atoi(strings.TrimSpace(t))
		return n
	case int:
		return t
	case nil:
		return 0
	default:
		return 0
	}
}
