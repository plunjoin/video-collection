package maccms

import (
	"crypto/md5"
	"encoding/hex"
	"encoding/xml"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// MacCMS XML 根定义 (<rss version="5.1">)
type xmlRssResponse struct {
	XMLName xml.Name      `xml:"rss"`
	Version string        `xml:"version,attr"`
	Class   []xmlClassTy  `xml:"class>ty"`
	List    xmlVideoList  `xml:"list"`
	Channel xmlRssChannel `xml:"channel"` // 兼容标准 RSS 2.0 feed
}

type xmlClassTy struct {
	ID   int    `xml:"id,attr"`
	Name string `xml:",chardata"`
}

type xmlVideoList struct {
	Page        int         `xml:"page,attr"`
	PageCount   int         `xml:"pagecount,attr"`
	PageSize    int         `xml:"pagesize,attr"`
	RecordCount int         `xml:"recordcount,attr"`
	Videos      []xmlVideo  `xml:"video"`
}

type xmlVideo struct {
	Last     string   `xml:"last"`
	ID       string   `xml:"id"`
	TID      int      `xml:"tid"`
	Name     string   `xml:"name"`
	Type     string   `xml:"type"`
	Pic      string   `xml:"pic"`
	Lang     string   `xml:"lang"`
	Area     string   `xml:"area"`
	Year     string   `xml:"year"`
	State    string   `xml:"state"`
	Note     string   `xml:"note"`
	Actor    string   `xml:"actor"`
	Director string   `xml:"director"`
	Des      string   `xml:"des"`
	DL       xmlDL    `xml:"dl"`
}

type xmlDL struct {
	DD []xmlDD `xml:"dd"`
}

type xmlDD struct {
	Flag  string `xml:"flag,attr"`
	Value string `xml:",chardata"`
}

// 兼容标准 RSS 2.0 频道定义
type xmlRssChannel struct {
	Title string       `xml:"title"`
	Items []xmlRssItem `xml:"item"`
}

type xmlRssItem struct {
	Title       string          `xml:"title"`
	Link        string          `xml:"link"`
	Category    string          `xml:"category"`
	PubDate     string          `xml:"pubDate"`
	Description string          `xml:"description"`
	Enclosure   xmlRssEnclosure `xml:"enclosure"`
}

type xmlRssEnclosure struct {
	URL  string `xml:"url,attr"`
	Type string `xml:"type,attr"`
}

// 兼容 Atom Feed
type atomFeed struct {
	XMLName xml.Name    `xml:"feed"`
	Title   string      `xml:"title"`
	Entries []atomEntry `xml:"entry"`
}

type atomEntry struct {
	Title     string     `xml:"title"`
	Link      atomLink   `xml:"link"`
	Category  atomCat    `xml:"category"`
	Published string     `xml:"published"`
	Updated   string     `xml:"updated"`
	Summary   string     `xml:"summary"`
	Content   string     `xml:"content"`
}

type atomLink struct {
	Href string `xml:"href,attr"`
	Rel  string `xml:"rel,attr"`
	Type string `xml:"type,attr"`
}

type atomCat struct {
	Term  string `xml:"term,attr"`
	Label string `xml:"label,attr"`
}

var (
	imgSrcRegex  = regexp.MustCompile(`(?i)<img[^>]+src=["']([^"']+)["']`)
	mediaURLRegex = regexp.MustCompile(`https?://[^\s"']+\.(?:m3u8|mp4|flv|mkv|webm)(?:\?[^\s"']*)?`)
)

// ParseXmlResponse 解析 XML 格式的响应数据 (自动兼容 MacCMS XML、RSS 2.0 与 Atom Feed)
func ParseXmlResponse(data []byte) (*MacCmsResponse, error) {
	// 1. 尝试解析 MacCMS / RSS 2.0 格式
	var rss xmlRssResponse
	if err := xml.Unmarshal(data, &rss); err == nil {
		// (A) 如果包含 MacCMS 规范的 <video> 节点
		if len(rss.List.Videos) > 0 || len(rss.Class) > 0 {
			return convertMacCmsXmlToResponse(&rss), nil
		}

		// (B) 如果包含标准 RSS 2.0 <item> 节点
		if len(rss.Channel.Items) > 0 {
			return convertRssChannelToResponse(&rss.Channel), nil
		}
	}

	// 2. 尝试解析 Atom Feed 格式
	var atom atomFeed
	if err := xml.Unmarshal(data, &atom); err == nil && len(atom.Entries) > 0 {
		return convertAtomFeedToResponse(&atom), nil
	}

	return nil, fmt.Errorf("xml response does not match MacCMS XML, RSS 2.0 or Atom format")
}

// convertMacCmsXmlToResponse 将 MacCMS XML 转换为系统统一响应结构
func convertMacCmsXmlToResponse(rss *xmlRssResponse) *MacCmsResponse {
	resp := &MacCmsResponse{
		Code:      1,
		Msg:       "XML数据解析成功",
		Page:      FlexInt(rss.List.Page),
		PageCount: FlexInt(rss.List.PageCount),
		Limit:     FlexInt(rss.List.PageSize),
		Total:     FlexInt(rss.List.RecordCount),
	}

	if resp.Page == 0 {
		resp.Page = 1
	}
	if resp.PageCount == 0 && len(rss.List.Videos) > 0 {
		resp.PageCount = 1
	}

	for _, c := range rss.Class {
		resp.Class = append(resp.Class, ClassItem{
			TypeID:   FlexInt(c.ID),
			TypeName: strings.TrimSpace(c.Name),
		})
	}

	for _, v := range rss.List.Videos {
		vodID, _ := strconv.Atoi(strings.TrimSpace(v.ID))
		if vodID == 0 {
			vodID = hashStringToPositiveInt(v.Name)
		}

		var fromList, urlList []string
		for _, dd := range v.DL.DD {
			flag := strings.TrimSpace(dd.Flag)
			if flag == "" {
				flag = "m3u8"
			}
			fromList = append(fromList, flag)
			urlList = append(urlList, strings.TrimSpace(dd.Value))
		}

		remarks := strings.TrimSpace(v.Note)
		if remarks == "" {
			remarks = strings.TrimSpace(v.State)
		}

		item := VodItem{
			VodID:       FlexInt(vodID),
			VodName:     strings.TrimSpace(v.Name),
			TypeID:      FlexInt(v.TID),
			TypeName:    strings.TrimSpace(v.Type),
			VodTime:     strings.TrimSpace(v.Last),
			VodRemarks:  remarks,
			VodPic:      strings.TrimSpace(v.Pic),
			VodActor:    strings.TrimSpace(v.Actor),
			VodDirector: strings.TrimSpace(v.Director),
			VodArea:     strings.TrimSpace(v.Area),
			VodLang:     strings.TrimSpace(v.Lang),
			VodYear:     strings.TrimSpace(v.Year),
			VodContent:  strings.TrimSpace(v.Des),
			VodPlayFrom: strings.Join(fromList, "$$$"),
			VodPlayURL:  strings.Join(urlList, "$$$"),
		}

		resp.List = append(resp.List, item)
	}

	return resp
}

// convertRssChannelToResponse 将标准 RSS 2.0 Feed 转换为系统统一响应结构
func convertRssChannelToResponse(ch *xmlRssChannel) *MacCmsResponse {
	resp := &MacCmsResponse{
		Code:      1,
		Msg:       "RSS 2.0 Feed 解析成功: " + ch.Title,
		Page:      1,
		PageCount: 1,
		Limit:     FlexInt(len(ch.Items)),
		Total:     FlexInt(len(ch.Items)),
	}

	for _, item := range ch.Items {
		title := strings.TrimSpace(item.Title)
		if title == "" {
			continue
		}

		vodID := hashStringToPositiveInt(item.Link + title)
		typeName := strings.TrimSpace(item.Category)
		if typeName == "" {
			typeName = "RSS订阅"
		}

		// 提取封面图片
		picURL := ""
		if strings.HasPrefix(item.Enclosure.Type, "image/") {
			picURL = item.Enclosure.URL
		}
		if picURL == "" {
			match := imgSrcRegex.FindStringSubmatch(item.Description)
			if len(match) > 1 {
				picURL = match[1]
			}
		}

		// 提取播放地址
		playURL := ""
		playFrom := "m3u8"
		if item.Enclosure.URL != "" && (strings.Contains(item.Enclosure.URL, ".m3u8") || strings.Contains(item.Enclosure.URL, ".mp4")) {
			playURL = "第01集$" + item.Enclosure.URL
			if strings.Contains(item.Enclosure.URL, ".mp4") {
				playFrom = "mp4"
			}
		} else {
			// 在正文或链接中寻找播放地址
			if m := mediaURLRegex.FindString(item.Description); m != "" {
				playURL = "正片$" + m
				if strings.Contains(m, ".mp4") {
					playFrom = "mp4"
				}
			} else if item.Link != "" {
				// 若直接为媒体链接或网页链接
				playURL = "正片$" + item.Link
				if strings.Contains(item.Link, ".mp4") {
					playFrom = "mp4"
				}
			}
		}

		// 格式化时间
		timeStr := parseRssDate(item.PubDate)

		vItem := VodItem{
			VodID:       FlexInt(vodID),
			VodName:     title,
			TypeName:    typeName,
			VodTime:     timeStr,
			VodPic:      picURL,
			VodContent:  cleanHTMLTags(item.Description),
			VodPlayFrom: playFrom,
			VodPlayURL:  playURL,
		}

		resp.List = append(resp.List, vItem)
	}

	return resp
}

// convertAtomFeedToResponse 将 Atom Feed 转换为系统统一响应结构
func convertAtomFeedToResponse(atom *atomFeed) *MacCmsResponse {
	resp := &MacCmsResponse{
		Code:      1,
		Msg:       "Atom Feed 解析成功: " + atom.Title,
		Page:      1,
		PageCount: 1,
		Limit:     FlexInt(len(atom.Entries)),
		Total:     FlexInt(len(atom.Entries)),
	}

	for _, entry := range atom.Entries {
		title := strings.TrimSpace(entry.Title)
		if title == "" {
			continue
		}

		link := entry.Link.Href
		vodID := hashStringToPositiveInt(link + title)

		cat := entry.Category.Label
		if cat == "" {
			cat = entry.Category.Term
		}
		if cat == "" {
			cat = "Atom订阅"
		}

		content := entry.Content
		if content == "" {
			content = entry.Summary
		}

		picURL := ""
		if m := imgSrcRegex.FindStringSubmatch(content); len(m) > 1 {
			picURL = m[1]
		}

		playURL := ""
		if m := mediaURLRegex.FindString(content); m != "" {
			playURL = "正片$" + m
		} else if link != "" {
			playURL = "正片$" + link
		}

		tStr := entry.Published
		if tStr == "" {
			tStr = entry.Updated
		}
		timeStr := parseRssDate(tStr)

		resp.List = append(resp.List, VodItem{
			VodID:       FlexInt(vodID),
			VodName:     title,
			TypeName:    cat,
			VodTime:     timeStr,
			VodPic:      picURL,
			VodContent:  cleanHTMLTags(content),
			VodPlayFrom: "m3u8",
			VodPlayURL:  playURL,
		})
	}

	return resp
}

func hashStringToPositiveInt(s string) int {
	h := md5.Sum([]byte(s))
	hexStr := hex.EncodeToString(h[:4])
	val, err := strconv.ParseInt(hexStr, 16, 64)
	if err != nil || val <= 0 {
		return int(time.Now().UnixNano() & 0x7FFFFFFF)
	}
	return int(val & 0x7FFFFFFF)
}

func parseRssDate(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Now().Format("2006-01-02 15:04:05")
	}

	formats := []string{
		time.RFC1123Z,
		time.RFC1123,
		time.RFC3339,
		time.RFC822Z,
		time.RFC822,
		"2006-01-02 15:04:05",
		"2006-01-02T15:04:05",
		"2006-01-02",
	}

	for _, f := range formats {
		if t, err := time.Parse(f, raw); err == nil {
			return t.Format("2006-01-02 15:04:05")
		}
	}
	return time.Now().Format("2006-01-02 15:04:05")
}

func cleanHTMLTags(html string) string {
	tagRegex := regexp.MustCompile(`<[^>]*>`)
	cleaned := tagRegex.ReplaceAllString(html, "")
	cleaned = strings.ReplaceAll(cleaned, "&nbsp;", " ")
	cleaned = strings.ReplaceAll(cleaned, "&amp;", "&")
	cleaned = strings.ReplaceAll(cleaned, "&lt;", "<")
	cleaned = strings.ReplaceAll(cleaned, "&gt;", ">")
	return strings.TrimSpace(cleaned)
}
