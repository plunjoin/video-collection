package maccms

import (
	"fmt"
	"strings"
)

// ParsePlayGroups 解析 MacCMS v10 特有的 vod_play_from 和 vod_play_url
// 规则：
// 1. 各播放源之间使用 "$$$" 分隔
// 2. 单个源内不同集数之间使用 "#" 分隔
// 3. 单集内名称与播放链接使用 "$" 分隔（如：第01集$http://xxx.m3u8）
func ParsePlayGroups(playFrom, playServer, playNote, playURL string) []PlayGroup {
	if strings.TrimSpace(playURL) == "" {
		return nil
	}

	fromList := splitByDelimiter(playFrom, "$$$")
	serverList := splitByDelimiter(playServer, "$$$")
	noteList := splitByDelimiter(playNote, "$$$")
	urlList := splitByDelimiter(playURL, "$$$")

	if len(fromList) == 0 {
		fromList = []string{"default"}
	}

	var groups []PlayGroup
	for i, rawURLGroup := range urlList {
		rawURLGroup = strings.TrimSpace(rawURLGroup)
		if rawURLGroup == "" {
			continue
		}

		playerCode := "unknown"
		if i < len(fromList) && strings.TrimSpace(fromList[i]) != "" {
			playerCode = strings.TrimSpace(fromList[i])
		} else if len(fromList) > 0 {
			playerCode = strings.TrimSpace(fromList[0])
		}

		server := "no"
		if i < len(serverList) {
			server = strings.TrimSpace(serverList[i])
		}

		note := ""
		if i < len(noteList) {
			note = strings.TrimSpace(noteList[i])
		}

		episodes := parseEpisodes(rawURLGroup)
		if len(episodes) > 0 {
			groups = append(groups, PlayGroup{
				PlayerCode: playerCode,
				Server:     server,
				Note:       note,
				Episodes:   episodes,
			})
		}
	}

	return groups
}

// parseEpisodes 解析单个播放源内的所有集数列表 (通过 "#" 分隔)
func parseEpisodes(rawGroup string) []Episode {
	parts := strings.Split(rawGroup, "#")
	var episodes []Episode

	for idx, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}

		// 单集使用 "$" 分隔
		subParts := strings.SplitN(part, "$", 2)
		if len(subParts) == 2 {
			epName := strings.TrimSpace(subParts[0])
			epURL := strings.TrimSpace(subParts[1])
			if epURL != "" {
				if epName == "" {
					epName = fmt.Sprintf("第%02d集", idx+1)
				}
				episodes = append(episodes, Episode{
					Name: epName,
					URL:  epURL,
				})
			}
		} else {
			// 没有 "$" 分隔符，直接作为链接
			epURL := strings.TrimSpace(subParts[0])
			if epURL != "" {
				episodes = append(episodes, Episode{
					Name: fmt.Sprintf("第%02d集", idx+1),
					URL:  epURL,
				})
			}
		}
	}

	return episodes
}

// splitByDelimiter 辅助安全切分字符串
func splitByDelimiter(s, delim string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	parts := strings.Split(s, delim)
	var res []string
	for _, p := range parts {
		res = append(res, strings.TrimSpace(p))
	}
	return res
}
