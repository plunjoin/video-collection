package m3u8cleaner

import (
	"bufio"
	"fmt"
	"math"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

// CleanOptions 定义切片广告过滤的配置选项
type CleanOptions struct {
	// EnableFilter 是否启用切片广告过滤
	EnableFilter bool
	// FilterHeadAd 是否过滤片头切片广告
	FilterHeadAd bool
	// MaxHeadAdDuration 片头切片广告最大判断时长（秒）
	MaxHeadAdDuration float64
	// FilterMiddleAd 是否过滤中插切片广告
	FilterMiddleAd bool
	// MaxMiddleAdDuration 中插切片广告最大判定时长（秒）
	MaxMiddleAdDuration float64
	// BlacklistKeywords 广告关键词黑名单
	BlacklistKeywords []string
	// ProxyBaseURL 本地 M3U8 代理接口基础路径
	ProxyBaseURL string
}

// DefaultOptions 返回开箱即用的默认过滤配置
func DefaultOptions() CleanOptions {
	return CleanOptions{
		EnableFilter:        true,
		FilterHeadAd:        true,
		MaxHeadAdDuration:   60.0, // 允许最长 60 秒的片头广告判定
		FilterMiddleAd:      true,
		MaxMiddleAdDuration: 90.0, // 允许最长 90 秒的中插广告判定
		BlacklistKeywords: []string{
			"guanggao",
			"ad.",
			"/ad/",
			"/ads/",
			"advert",
			"union",
			"adwords",
			"open.ad",
			"tg.mp4",
			"tg.ts",
			"banner",
		},
		ProxyBaseURL: "/api/m3u8/clean",
	}
}

// segmentItem 表示一个 TS 切片片段及其元数据
type segmentItem struct {
	duration float64  // 切片时长（从 EXTINF 获取）
	extinf   string   // 原始 EXTINF 行内容
	extra    []string // 切片前可能存在的其他标签（例如 #EXT-X-KEY 等）
	uri      string   // 切片原始 URI
	resolved string   // 补全后的绝对 URI
	seq      int64    // 提取出的数字序号（如 73, 33175）
	hasSeq   bool     // 是否成功提取出数字序号
	isAd     bool     // 是否判定为广告切片
}

// segmentGroup 表示被 #EXT-X-DISCONTINUITY 分隔的一组切片
type segmentGroup struct {
	hasLeadingDiscontinuity bool
	items                   []*segmentItem
	totalDuration           float64
	minSeq                  int64
	maxSeq                  int64
	hasSeq                  bool
}

var (
	extinfRegex = regexp.MustCompile(`^#EXTINF:\s*([0-9.]+)(?:,(.*))?`)
	// 匹配扩展名前完整的连续数字串；数字前缀可能与序号连在一起，超过 12 位。
	// 保留完整数值用于比较跳变，由 ParseInt 检查 int64 溢出，避免截断后误判。
	tsSeqRegex = regexp.MustCompile(`(?:^|[^0-9])([0-9]+)\.(?:ts|image|jpeg|jpg|png|webp|m4s|mp4)`)
)

// extractTSSeq 尝试从切片路径中提取数字序号
func extractTSSeq(uri string) (int64, bool) {
	cleanURI := uri
	if idx := strings.Index(cleanURI, "?"); idx != -1 {
		cleanURI = cleanURI[:idx]
	}
	if idx := strings.LastIndex(cleanURI, "/"); idx != -1 {
		cleanURI = cleanURI[idx+1:]
	}

	matches := tsSeqRegex.FindStringSubmatch(cleanURI)
	if len(matches) > 1 {
		n, err := strconv.ParseInt(matches[1], 10, 64)
		if err == nil {
			return n, true
		}
	}
	return -1, false
}

// CleanM3U8 解析并清洗 M3U8 文本，剔除切片广告并重写 URL 为绝对路径
func CleanM3U8(content string, originURL string, opts CleanOptions) (string, error) {
	parsedOrigin, err := url.Parse(originURL)
	if err != nil {
		return content, fmt.Errorf("invalid originURL: %w", err)
	}

	scanner := bufio.NewScanner(strings.NewReader(content))
	var lines []string
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		return content, err
	}

	// 1. 检查是否为 Master Playlist（主索引播放列表，包含多个子流分辨率）
	isMaster := false
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#EXT-X-STREAM-INF:") {
			isMaster = true
			break
		}
	}

	if isMaster {
		return rewriteMasterPlaylist(lines, parsedOrigin, opts.ProxyBaseURL), nil
	}

	// 2. 处理 Media Playlist（实际切片列表）
	return processMediaPlaylist(lines, parsedOrigin, opts)
}

// rewriteMasterPlaylist 重写 Master Playlist 中的子 m3u8 地址为本代理服务的地址
func rewriteMasterPlaylist(lines []string, originURL *url.URL, proxyBaseURL string) string {
	var out []string
	if proxyBaseURL == "" {
		proxyBaseURL = "/api/m3u8/clean"
	}

	for i := 0; i < len(lines); i++ {
		line := lines[i]
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			out = append(out, line)
			continue
		}

		if strings.HasPrefix(trimmed, "#") {
			out = append(out, line)
			continue
		}

		// 这一行是子 m3u8 地址
		resolved := resolveAbsoluteURL(originURL, trimmed)
		rewritten := fmt.Sprintf("%s?url=%s", proxyBaseURL, url.QueryEscape(resolved))
		out = append(out, rewritten)
	}

	return strings.Join(out, "\n")
}

// finalizeGroup 计算组内的序号统计特征
func finalizeGroup(grp *segmentGroup) {
	if len(grp.items) == 0 {
		return
	}
	var minVal int64 = math.MaxInt64
	var maxVal int64 = -1
	countWithSeq := 0

	for _, itm := range grp.items {
		if itm.hasSeq {
			if itm.seq < minVal {
				minVal = itm.seq
			}
			if itm.seq > maxVal {
				maxVal = itm.seq
			}
			countWithSeq++
		}
	}

	// 若该组大多数切片都有数字序号，标记该组拥有序号特征
	if countWithSeq > 0 && countWithSeq >= len(grp.items)/2 {
		grp.minSeq = minVal
		grp.maxSeq = maxVal
		grp.hasSeq = true
	}
}

// isSequenceDetour 判断中间组是否偏离前后严格连续的正片序列。
// 使用实际相邻切片，且要求中间所有切片都有序号、整体落在正片边界同一侧。
func isSequenceDetour(prev, curr, next *segmentGroup) bool {
	if len(prev.items) == 0 || len(curr.items) == 0 || len(next.items) == 0 {
		return false
	}
	before := prev.items[len(prev.items)-1]
	after := next.items[0]
	if !before.hasSeq || !after.hasSeq || after.seq-before.seq != 1 {
		return false
	}
	allHigher, allLower := true, true
	for _, item := range curr.items {
		if !item.hasSeq {
			return false
		}
		allHigher = allHigher && item.seq > after.seq
		allLower = allLower && item.seq < before.seq
	}
	return allHigher || allLower
}

// processMediaPlaylist 处理正片切片清单，执行广告过滤与路径补全
func processMediaPlaylist(lines []string, originURL *url.URL, opts CleanOptions) (string, error) {
	var headerLines []string
	var footerLines []string

	var groups []*segmentGroup
	currentGroup := &segmentGroup{hasLeadingDiscontinuity: false}

	var currentExtinf string
	var currentExtra []string
	var currentDuration float64
	mediaSeq := 0
	mediaSeqLineIdx := -1

	// 解析各行
	for i := 0; i < len(lines); i++ {
		line := lines[i]
		trimmed := strings.TrimSpace(line)

		if trimmed == "" {
			continue
		}

		// 读取起始序列号
		if strings.HasPrefix(trimmed, "#EXT-X-MEDIA-SEQUENCE:") {
			parts := strings.SplitN(trimmed, ":", 2)
			if len(parts) == 2 {
				mediaSeq, _ = strconv.Atoi(strings.TrimSpace(parts[1]))
			}
			mediaSeqLineIdx = len(headerLines)
			headerLines = append(headerLines, line)
			continue
		}

		// 检测 DISCONTINUITY 标签：开启一个新的 Group
		if trimmed == "#EXT-X-DISCONTINUITY" {
			if len(currentGroup.items) > 0 {
				finalizeGroup(currentGroup)
				groups = append(groups, currentGroup)
			}
			currentGroup = &segmentGroup{hasLeadingDiscontinuity: true}
			continue
		}

		// 处理结束标签
		if trimmed == "#EXT-X-ENDLIST" {
			footerLines = append(footerLines, line)
			continue
		}

		// 处理切片时长信息
		if strings.HasPrefix(trimmed, "#EXTINF:") {
			currentExtinf = line
			matches := extinfRegex.FindStringSubmatch(trimmed)
			if len(matches) > 1 {
				currentDuration, _ = strconv.ParseFloat(matches[1], 64)
			}
			continue
		}

		// 处理密钥标签（把相对路径密钥补全为绝对路径）
		if strings.HasPrefix(trimmed, "#EXT-X-KEY:") {
			resolvedKeyLine := resolveKeyURIAbsolute(trimmed, originURL)
			currentExtra = append(currentExtra, resolvedKeyLine)
			continue
		}

		// 其他全局/头部标签（如 #EXTM3U, #EXT-X-VERSION 等）
		if strings.HasPrefix(trimmed, "#") {
			if len(groups) == 0 && len(currentGroup.items) == 0 && currentExtinf == "" {
				headerLines = append(headerLines, line)
			} else {
				currentExtra = append(currentExtra, line)
			}
			continue
		}

		// 这一行是切片 URI
		resolvedURI := resolveAbsoluteURL(originURL, trimmed)
		seq, hasSeq := extractTSSeq(trimmed)
		item := &segmentItem{
			duration: currentDuration,
			extinf:   currentExtinf,
			extra:    currentExtra,
			uri:      trimmed,
			resolved: resolvedURI,
			seq:      seq,
			hasSeq:   hasSeq,
		}

		// 检查关键词黑名单
		if opts.EnableFilter && isBlacklisted(item.resolved, opts.BlacklistKeywords) {
			item.isAd = true
		}

		currentGroup.items = append(currentGroup.items, item)
		currentGroup.totalDuration += item.duration

		// 重置当前暂存变量
		currentExtinf = ""
		currentExtra = nil
		currentDuration = 0
	}

	if len(currentGroup.items) > 0 {
		finalizeGroup(currentGroup)
		groups = append(groups, currentGroup)
	}

	// 3. 执行智能切片广告过滤
	deletedCount := 0
	if opts.EnableFilter && len(groups) > 0 {
		isGroupAd := make([]bool, len(groups))

		// (A) 判定中插广告 (重点：序号突变跳变算法 Sequence Discontinuity Detection)
		if opts.FilterMiddleAd && len(groups) >= 3 {
			for i := 1; i < len(groups)-1; i++ {
				curr := groups[i]
				prev := groups[i-1]
				next := groups[i+1]

				// 必须是被 DISCONTINUITY 包裹的片段，且时长在广告阈值内
				if !curr.hasLeadingDiscontinuity || curr.totalDuration > opts.MaxMiddleAdDuration {
					continue
				}

				// 前后正片严格续接（如 15000073 -> 15000074），中间组整体偏离序列。
				// 不要求广告序号更大，也不要求跳变超过 50。
				if isSequenceDetour(prev, curr, next) {
					isGroupAd[i] = true
					continue
				}

				// 规则 1：基于序号剧烈突变的插播广告识别
				if prev.hasSeq && curr.hasSeq && next.hasSeq {
					jumpForward := curr.minSeq - prev.maxSeq
					jumpBackward := curr.maxSeq - next.minSeq
					mainStreamDiff := next.minSeq - prev.maxSeq

					// 场景：正片从 prev.maxSeq (如 73) 顺延到 next.minSeq (如 74，diff<=15)
					// 而中间插入的 curr.minSeq (如 33175，跳变值>50)
					if jumpForward > 50 && jumpBackward > 50 && mainStreamDiff >= 0 && mainStreamDiff <= 15 {
						isGroupAd[i] = true
						continue
					}

					// 场景：即使后一组没有严格递接，但当前组序号远大于前后组（如当前组序号上万，前后组均小于 1000）
					if curr.minSeq >= 10000 && prev.maxSeq < 2000 && next.minSeq < 2000 {
						isGroupAd[i] = true
						continue
					}
				}

				// 规则 2：纯时长短片段中插广告（当前后组切片很多，而当前组切片很少且时长很短，切片时长整齐如 4.000s）
				if curr.totalDuration <= 20.0 && len(curr.items) <= 6 && len(prev.items) >= 8 && len(next.items) >= 8 {
					isGroupAd[i] = true
					continue
				}
			}
		}

		// (B) 判定片头广告
		// 已识别的中插广告不能作为片头/片尾判断的正片参照。
		if opts.FilterHeadAd && len(groups) >= 2 && !isGroupAd[1] {
			head := groups[0]
			next := groups[1]

			if head.totalDuration <= opts.MaxHeadAdDuration {
				// 规则 1：如果片头切片序号很大（如广告池 14175~），而第二组正片从 0 开始
				if head.hasSeq && next.hasSeq && head.minSeq > 1000 && next.minSeq <= 5 {
					isGroupAd[0] = true
				} else if next.hasLeadingDiscontinuity && head.totalDuration <= opts.MaxHeadAdDuration {
					// 规则 2：如果第一组之后紧跟 DISCONTINUITY，且第一组时长较短，且不是从正片 0 递增
					if head.hasSeq && next.hasSeq && head.maxSeq >= next.minSeq {
						isGroupAd[0] = true
					}
				}
			}
		}

		// (C) 判定片尾广告
		if len(groups) >= 2 {
			lastIdx := len(groups) - 1
			last := groups[lastIdx]
			prev := groups[lastIdx-1]

			if !isGroupAd[lastIdx-1] && last.totalDuration <= opts.MaxMiddleAdDuration && last.hasLeadingDiscontinuity {
				if last.hasSeq && prev.hasSeq && last.minSeq-prev.maxSeq > 100 {
					isGroupAd[lastIdx] = true
				}
			}
		}

		// 构建剔除广告后的新分组列表，并平滑处理 DISCONTINUITY
		var cleanGroups []*segmentGroup
		for idx, grp := range groups {
			if isGroupAd[idx] {
				deletedCount += len(grp.items)
				continue
			}
			cleanGroups = append(cleanGroups, grp)
		}

		// 平滑恢复连续切片之间的 DISCONTINUITY：
		// 如果第 i 组和第 i-1 组在正片序列上是连续的（如序号 73 接 74），消除它们之间的 DISCONTINUITY
		for i := 1; i < len(cleanGroups); i++ {
			prev := cleanGroups[i-1]
			curr := cleanGroups[i]
			if prev.hasSeq && curr.hasSeq {
				diff := curr.minSeq - prev.maxSeq
				if diff >= 0 && diff <= 2 {
					// 序号原本是连续的，抹去广告留下的不连续标记
					curr.hasLeadingDiscontinuity = false
				}
			}
		}

		// 如果第一组带有 leading discontinuity，清除它
		if len(cleanGroups) > 0 {
			cleanGroups[0].hasLeadingDiscontinuity = false
		}

		groups = cleanGroups
	}

	// 4. 重构输出 M3U8
	var outLines []string

	// 如果有切片被删除，更新 MEDIA-SEQUENCE 保证序号连续
	if deletedCount > 0 && mediaSeqLineIdx >= 0 && mediaSeqLineIdx < len(headerLines) {
		headerLines[mediaSeqLineIdx] = fmt.Sprintf("#EXT-X-MEDIA-SEQUENCE:%d", mediaSeq+deletedCount)
	}

	outLines = append(outLines, headerLines...)

	for gIdx, grp := range groups {
		// 写入不连续标记
		if grp.hasLeadingDiscontinuity && gIdx > 0 {
			outLines = append(outLines, "#EXT-X-DISCONTINUITY")
		}

		for _, itm := range grp.items {
			// 跳过单独命中了黑名单关键词的广告切片
			if itm.isAd {
				continue
			}

			// 写入切片关联的前置标签（如 KEY 等）
			for _, ex := range itm.extra {
				outLines = append(outLines, ex)
			}
			// 写入 EXTINF
			if itm.extinf != "" {
				outLines = append(outLines, itm.extinf)
			}
			// 写入补全后的绝对 TS URL
			outLines = append(outLines, itm.resolved)
		}
	}

	// 写入尾部（如 ENDLIST）
	outLines = append(outLines, footerLines...)

	return strings.Join(outLines, "\n"), nil
}

// isBlacklisted 检查 URL 是否匹配黑名单关键词
func isBlacklisted(rawURL string, keywords []string) bool {
	lower := strings.ToLower(rawURL)
	for _, kw := range keywords {
		if strings.Contains(lower, strings.ToLower(kw)) {
			return true
		}
	}
	return false
}

// resolveAbsoluteURL 将相对路径结合基准 URL 转换为完整的绝对 URL
func resolveAbsoluteURL(base *url.URL, relativePath string) string {
	relativePath = strings.TrimSpace(relativePath)
	if strings.HasPrefix(relativePath, "http://") || strings.HasPrefix(relativePath, "https://") {
		return relativePath
	}

	rel, err := url.Parse(relativePath)
	if err != nil {
		return relativePath
	}

	return base.ResolveReference(rel).String()
}

// resolveKeyURIAbsolute 替换 #EXT-X-KEY 中的相对 URI="key.key" 为绝对路径
func resolveKeyURIAbsolute(keyLine string, base *url.URL) string {
	uriIdx := strings.Index(keyLine, "URI=\"")
	if uriIdx == -1 {
		return keyLine
	}

	start := uriIdx + 5
	end := strings.Index(keyLine[start:], "\"")
	if end == -1 {
		return keyLine
	}
	rawURI := keyLine[start : start+end]
	resolved := resolveAbsoluteURL(base, rawURI)

	return keyLine[:start] + resolved + keyLine[start+end:]
}
