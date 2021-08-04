package maccms

import (
	"fmt"
	"regexp"
	"strings"

	"video-collection-api/config"
)

// FilterEngine 数据过滤与规则清洗执行器
type FilterEngine struct {
	sourceCfg config.SourceConfig
	regexes   []compiledRegex
}

type compiledRegex struct {
	re          *regexp.Regexp
	replacement string
}

// NewFilterEngine 创建过滤器实例
func NewFilterEngine(sourceCfg config.SourceConfig) *FilterEngine {
	fe := &FilterEngine{
		sourceCfg: sourceCfg,
	}

	for _, rule := range sourceCfg.Filter.ContentReplacePatterns {
		if rule.IsRegex {
			if re, err := regexp.Compile(rule.Pattern); err == nil {
				fe.regexes = append(fe.regexes, compiledRegex{re: re, replacement: rule.Replacement})
			}
		}
	}
	return fe
}

// CleanAndTransform 根据配置清洗并转换单个原始视频条目
// 返回 (清洗后的结构体, 是否保留)。如果被规则过滤掉则返回 (nil, false)
func (fe *FilterEngine) CleanAndTransform(raw VodItem) (*CleanedVod, bool) {
	rule := fe.sourceCfg.Filter

	// 1. 分类黑名单过滤
	for _, ignoreTypeID := range rule.IgnoreTypeIDs {
		if raw.TypeID.Int() == ignoreTypeID {
			return nil, false
		}
	}

	// 2. 片名黑名单词过滤
	for _, kw := range rule.IgnoreNameKeywords {
		if kw != "" && strings.Contains(raw.VodName, kw) {
			return nil, false
		}
	}

	// 3. 片名清洗：去除前缀
	cleanName := raw.VodName
	for _, prefix := range rule.NameCleanPrefixes {
		if prefix != "" && strings.HasPrefix(cleanName, prefix) {
			cleanName = strings.TrimPrefix(cleanName, prefix)
		}
	}
	cleanName = strings.TrimSpace(cleanName)
	if cleanName == "" {
		return nil, false
	}

	// 4. 解析并过滤播放源与集数
	rawPlayGroups := ParsePlayGroups(raw.VodPlayFrom, raw.VodPlayServer, raw.VodPlayNote, raw.VodPlayURL)
	var finalPlayGroups []PlayGroup

	for _, group := range rawPlayGroups {
		code := strings.ToLower(strings.TrimSpace(group.PlayerCode))

		// 播放器标识重命名映射
		if mapped, ok := rule.PlayerMappings[code]; ok && mapped != "" {
			code = mapped
		}

		// 播放器白名单检查
		if len(rule.AllowedPlayers) > 0 {
			allowed := false
			for _, allowedCode := range rule.AllowedPlayers {
				if strings.EqualFold(code, allowedCode) {
					allowed = true
					break
				}
			}
			if !allowed {
				continue
			}
		}

		// 自动过滤网页分享/非直链播放线路 (如 feifan 默认附带的 /share/ 网页内嵌地址)，确保播放器均可直接解析流媒体
		if len(group.Episodes) > 0 {
			firstURL := strings.ToLower(group.Episodes[0].URL)
			if strings.Contains(firstURL, "/share/") && !strings.Contains(firstURL, ".m3u8") && !strings.Contains(firstURL, ".mp4") {
				continue
			}
		}

		if len(group.Episodes) > 0 {
			group.PlayerCode = code
			group.SourceID = fe.sourceCfg.ID
			group.SourceName = fe.sourceCfg.Name
			if group.SourceName == "" {
				group.SourceName = fe.sourceCfg.ID
			}
			group.From = fmt.Sprintf("%s (%s)", group.SourceName, code)
			if group.Server == "" || group.Server == "no" {
				group.Server = group.SourceName
			}
			finalPlayGroups = append(finalPlayGroups, group)
		}
	}

	// 5. 校验播放链接
	if rule.RequirePlayURLs && len(finalPlayGroups) == 0 {
		return nil, false
	}

	// 6. 分类映射匹配
	targetTypeID := 0
	targetTypeName := raw.TypeName
	for _, mapping := range fe.sourceCfg.CategoryMappings {
		if mapping.SourceTypeID == raw.TypeID.Int() || (mapping.SourceTypeName != "" && mapping.SourceTypeName == raw.TypeName) {
			targetTypeID = mapping.TargetTypeID
			targetTypeName = mapping.TargetTypeName
			break
		}
	}

	// 7. 内容引流广告清洗
	content := raw.VodContent
	for _, rule := range fe.sourceCfg.Filter.ContentReplacePatterns {
		if !rule.IsRegex && rule.Pattern != "" {
			content = strings.ReplaceAll(content, rule.Pattern, rule.Replacement)
		}
	}
	for _, cr := range fe.regexes {
		content = cr.re.ReplaceAllString(content, cr.replacement)
	}

	cleaned := &CleanedVod{
		OriginalID:     raw.VodID.Int(),
		SourceID:       fe.sourceCfg.ID,
		SourceName:     fe.sourceCfg.Name,
		Name:           cleanName,
		SubName:        raw.VodSub,
		TargetTypeID:   targetTypeID,
		TargetTypeName: targetTypeName,
		SourceTypeName: raw.TypeName,
		Picture:        raw.VodPic,
		Actor:          raw.VodActor,
		Director:       raw.VodDirector,
		Area:           raw.VodArea,
		Language:       raw.VodLang,
		Year:           raw.VodYear,
		Remarks:        raw.VodRemarks,
		Content:        strings.TrimSpace(content),
		UpdateTime:     raw.VodTime,
		PlayGroups:     finalPlayGroups,
	}

	return cleaned, true
}
