package maccms

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"video-collection-api/config"
)

// ParseCustomJsonResponse 解析任意自定义结构的 JSON API
func ParseCustomJsonResponse(data []byte, mapping config.CustomMapping) (*MacCmsResponse, error) {
	var raw any
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("json unmarshal failed: %w", err)
	}

	// 1. 定位列表数据
	listPath := strings.TrimSpace(mapping.ListPath)
	if listPath == "" {
		listPath = "data" // 默认常见路径
	}

	rawItems := extractSliceByPath(raw, listPath)
	if len(rawItems) == 0 {
		// 尝试根直接为数组
		if slice, ok := raw.([]any); ok {
			rawItems = slice
		} else {
			// 尝试常见的其他列表名称
			for _, candidate := range []string{"list", "items", "results", "videos", "data.list", "data.items"} {
				if s := extractSliceByPath(raw, candidate); len(s) > 0 {
					rawItems = s
					break
				}
			}
		}
	}

	resp := &MacCmsResponse{
		Code:      1,
		Msg:       "自定义JSON解析成功",
		Page:      1,
		PageCount: 1,
		Limit:     FlexInt(len(rawItems)),
		Total:     FlexInt(len(rawItems)),
	}

	// 2. 遍历提取字段
	for idx, item := range rawItems {
		itemMap, ok := item.(map[string]any)
		if !ok {
			continue
		}

		name := extractStringField(itemMap, mapping.NamePath, "name", "title", "vod_name", "video_name")
		if name == "" {
			continue
		}

		idVal := extractStringField(itemMap, mapping.IDPath, "id", "vod_id", "video_id")
		vodID := 0
		if idVal != "" {
			vodID = hashStringToPositiveInt(idVal)
		} else {
			vodID = hashStringToPositiveInt(fmt.Sprintf("%s_%d", name, idx))
		}

		typeName := extractStringField(itemMap, mapping.TypePath, "type_name", "type", "category", "channel")
		if typeName == "" {
			typeName = "未分类"
		}

		pic := extractStringField(itemMap, mapping.PicPath, "pic", "picture", "cover", "thumb", "poster", "vod_pic")
		playURL := extractStringField(itemMap, mapping.PlayURLPath, "play_url", "url", "video_url", "src", "link", "m3u8")
		remarks := extractStringField(itemMap, mapping.RemarksPath, "remarks", "note", "state", "episode", "vod_remarks")
		actor := extractStringField(itemMap, mapping.ActorPath, "actor", "actors", "vod_actor")
		director := extractStringField(itemMap, mapping.DirectorPath, "director", "directors", "vod_director")
		area := extractStringField(itemMap, mapping.AreaPath, "area", "region", "vod_area")
		year := extractStringField(itemMap, mapping.YearPath, "year", "pub_year", "vod_year")
		content := extractStringField(itemMap, mapping.ContentPath, "content", "des", "description", "summary", "vod_content")

		// 格式化播放地址
		vodPlayURL := playURL
		if vodPlayURL != "" && !strings.Contains(vodPlayURL, "$") {
			vodPlayURL = "正片$" + vodPlayURL
		}

		vodItem := VodItem{
			VodID:       FlexInt(vodID),
			VodName:     name,
			TypeName:    typeName,
			VodPic:      pic,
			VodActor:    actor,
			VodDirector: director,
			VodArea:     area,
			VodYear:     year,
			VodRemarks:  remarks,
			VodContent:  content,
			VodPlayFrom: "m3u8",
			VodPlayURL:  vodPlayURL,
			VodTime:     time.Now().Format("2006-01-02 15:04:05"),
		}

		resp.List = append(resp.List, vodItem)
	}

	return resp, nil
}

func extractSliceByPath(root any, path string) []any {
	parts := strings.Split(strings.TrimSpace(path), ".")
	current := root

	for _, part := range parts {
		if part == "" {
			continue
		}
		m, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current = m[part]
	}

	if slice, ok := current.([]any); ok {
		return slice
	}
	return nil
}

func extractStringField(item map[string]any, specificField string, fallbacks ...string) string {
	if specificField != "" {
		if val, exists := item[specificField]; exists && val != nil {
			return fmt.Sprintf("%v", val)
		}
	}

	for _, fb := range fallbacks {
		if val, exists := item[fb]; exists && val != nil {
			return fmt.Sprintf("%v", val)
		}
	}
	return ""
}
