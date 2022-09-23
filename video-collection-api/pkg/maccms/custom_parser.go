package maccms

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"video-collection-api/config"
)

// ParseCustomJsonResponse 解析任意自定义结构的 JSON API
func ParseCustomJsonResponse(data []byte, mapping config.CustomMapping) (*MacCmsResponse, error) {
	var raw any
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.UseNumber()
	if err := decoder.Decode(&raw); err != nil {
		return nil, fmt.Errorf("json unmarshal failed: %w", err)
	}

	// 1. 定位列表数据
	listPath := strings.TrimSpace(mapping.ListPath)
	if listPath == "" {
		listPath = "data" // 默认常见路径
	}

	rawItems := extractSliceByPath(raw, listPath)
	if rawItems == nil && strings.TrimSpace(mapping.ListPath) == "" {
		// 尝试根直接为数组
		if slice, ok := raw.([]any); ok {
			rawItems = slice
		} else {
			// 尝试常见的其他列表名称
			for _, candidate := range []string{"list", "items", "results", "videos", "data.list", "data.items"} {
				if s := extractSliceByPath(raw, candidate); s != nil {
					rawItems = s
					break
				}
			}
		}
	}

	if rawItems == nil {
		return nil, fmt.Errorf("列表路径 %q 未指向数组", listPath)
	}
	resp := &MacCmsResponse{
		Code:      1,
		Msg:       "自定义JSON解析成功",
		Page:      1,
		PageCount: 1,
		Limit:     FlexInt(len(rawItems)),
		Total:     FlexInt(len(rawItems)),
	}

	number := func(path string, fallback FlexInt) FlexInt {
		if path == "" {
			return fallback
		}
		n, _ := strconv.Atoi(fmt.Sprint(extractValueByPath(raw, path)))
		return FlexInt(n)
	}
	resp.Page = number(mapping.PagePath, 1)
	resp.PageCount = number(mapping.PageCountPath, 1)
	resp.Total = number(mapping.TotalPath, resp.Total)
	if resp.PageCount < 1 {
		resp.PageCount = 1
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

		player := extractStringField(itemMap, mapping.PlayFromPath)
		if player == "" {
			player = "m3u8"
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
			VodPlayFrom: player,
			VodPlayURL:  vodPlayURL,
			VodTime:     time.Now().Format("2006-01-02 15:04:05"),
		}

		resp.List = append(resp.List, vodItem)
	}

	return resp, nil
}

func extractValueByPath(root any, path string) any {
	if path == "" || path == "$" {
		return root
	}
	current := root
	for _, part := range strings.Split(strings.TrimPrefix(path, "$."), ".") {
		switch obj := current.(type) {
		case map[string]any:
			current = obj[part]
		case []any:
			i, err := strconv.Atoi(part)
			if err != nil || i < 0 || i >= len(obj) {
				return nil
			}
			current = obj[i]
		default:
			return nil
		}
	}
	return current
}

func extractSliceByPath(root any, path string) []any {
	list, _ := extractValueByPath(root, path).([]any)
	return list
}

func extractStringField(item map[string]any, specificField string, fallbacks ...string) string {
	if specificField != "" {
		if val := extractValueByPath(item, specificField); val != nil {
			return fmt.Sprint(val)
		}
		return ""
	}
	for _, fb := range fallbacks {
		if val := extractValueByPath(item, fb); val != nil {
			return fmt.Sprint(val)
		}
	}
	return ""
}
