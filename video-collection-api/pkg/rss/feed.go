package rss

import (
	"encoding/xml"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"video-collection-api/pkg/store"
)

// Handler 网页 RSS 2.0 订阅服务处理器
type Handler struct {
	store store.Store
}

// NewHandler 创建 RSS 处理器
func NewHandler(s store.Store) *Handler {
	return &Handler{store: s}
}

// RSSChannel RSS 2.0 channel 根模型
type RSSChannel struct {
	XMLName       xml.Name    `xml:"channel"`
	Title         string      `xml:"title"`
	Link          string      `xml:"link"`
	Description   string      `xml:"description"`
	Language      string      `xml:"language"`
	PubDate       string      `xml:"pubDate,omitempty"`
	LastBuildDate string      `xml:"lastBuildDate,omitempty"`
	Generator     string      `xml:"generator"`
	AtomLink      AtomLink    `xml:"atom:link"`
	Items         []RSSItem   `xml:"item"`
}

// AtomLink Atom 自关联
type AtomLink struct {
	Href string `xml:"href,attr"`
	Rel  string `xml:"rel,attr"`
	Type string `xml:"type,attr"`
}

// RSSItem 单个订阅条目
type RSSItem struct {
	Title       CDATAText    `xml:"title"`
	Link        string       `xml:"link"`
	GUID        RSSGUID      `xml:"guid"`
	Category    CDATAText    `xml:"category"`
	PubDate     string       `xml:"pubDate"`
	Description CDATAText    `xml:"description"`
	Enclosure   *RSSEnclosure `xml:"enclosure,omitempty"`
}

// RSSGUID 唯一标识
type RSSGUID struct {
	IsPermaLink bool   `xml:"isPermaLink,attr"`
	Value       string `xml:",chardata"`
}

// RSSEnclosure 媒体附件(海报封面图)
type RSSEnclosure struct {
	URL    string `xml:"url,attr"`
	Type   string `xml:"type,attr"`
	Length int64  `xml:"length,attr"`
}

// CDATAText 支持输出 CDATA 包装的 XML 文本
type CDATAText struct {
	Text string `xml:",cdata"`
}

// RSSFeed 根 XML 容器
type RSSFeed struct {
	XMLName xml.Name   `xml:"rss"`
	Version string     `xml:"version,attr"`
	AtomNS  string     `xml:"xmlns:atom,attr"`
	Channel RSSChannel `xml:"channel"`
}

// ServeHTTP 处理 RSS 订阅请求
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	q := r.URL.Query()

	// 1. 获取站点基础设置
	siteName, _ := h.store.GetSetting(ctx, "site_name", "影视聚合Portal")
	siteDesc, _ := h.store.GetSetting(ctx, "site_subtitle", "海量超清影视 • 智能聚合播放")
	if siteDesc == "" {
		siteDesc, _ = h.store.GetSetting(ctx, "site_desc", "全网影视聚合更新订阅")
	}

	// 2. 解析过滤与分页参数
	limit := 30
	if limitStr := q.Get("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	typeID, _ := strconv.Atoi(q.Get("type_id"))
	hours, _ := strconv.Atoi(q.Get("hours"))
	if hours <= 0 {
		hours, _ = strconv.Atoi(q.Get("h"))
	}
	keyword := strings.TrimSpace(q.Get("keyword"))
	if keyword == "" {
		keyword = strings.TrimSpace(q.Get("wd"))
	}

	// 3. 构造基础域名与链接
	scheme := "http"
	if r.TLS != nil || r.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	host := r.Host
	if host == "" {
		host = "localhost"
	}
	baseURL := fmt.Sprintf("%s://%s", scheme, host)
	selfURL := fmt.Sprintf("%s%s", baseURL, r.URL.RequestURI())

	// 4. 查询视频
	vQuery := store.VideoQuery{
		Page:      1,
		PageSize:  limit,
		TypeID:    typeID,
		Hours:     hours,
		Keyword:   keyword,
		OrderBy:   "updated_at",
		OrderDesc: true,
	}

	records, _, err := h.store.QueryVideos(ctx, vQuery)
	if err != nil {
		http.Error(w, "Query video error: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// 5. 组装 Feed 标题
	channelTitle := siteName + " - 影视更新订阅"
	if typeID > 0 {
		cats, _ := h.store.GetCategories(ctx)
		for _, c := range cats {
			if c.ID == typeID {
				channelTitle = fmt.Sprintf("%s - %s专区 RSS 订阅", siteName, c.Name)
				break
			}
		}
	} else if keyword != "" {
		channelTitle = fmt.Sprintf("%s - 搜索[%s] 订阅", siteName, keyword)
	}

	nowStr := time.Now().Format(time.RFC1123Z)
	lastBuildDate := nowStr
	if len(records) > 0 {
		lastBuildDate = records[0].UpdatedAt.Format(time.RFC1123Z)
	}

	// 6. 转换 Item
	var items []RSSItem
	for _, rec := range records {
		detailURL := fmt.Sprintf("%s/detail?id=%d", baseURL, rec.ID)

		titleText := rec.Name
		if rec.Remarks != "" {
			titleText = fmt.Sprintf("%s (%s)", rec.Name, rec.Remarks)
		}

		// 格式化富文本描述（含海报、分类、演职员、简介与线路说明）
		var descBuilder strings.Builder
		descBuilder.WriteString("<div style=\"font-family: sans-serif; line-height: 1.6;\">")
		if rec.Picture != "" {
			descBuilder.WriteString(fmt.Sprintf(
				"<p><a href=\"%s\" target=\"_blank\"><img src=\"%s\" alt=\"%s\" style=\"max-width: 220px; border-radius: 8px; box-shadow: 0 4px 10px rgba(0,0,0,0.15);\" /></a></p>",
				detailURL, rec.Picture, rec.Name,
			))
		}
		descBuilder.WriteString(fmt.Sprintf("<p><strong>片名：</strong><a href=\"%s\">%s</a></p>", detailURL, rec.Name))
		if rec.TypeName != "" {
			descBuilder.WriteString(fmt.Sprintf("<p><strong>分类：</strong>%s</p>", rec.TypeName))
		}
		if rec.Remarks != "" {
			descBuilder.WriteString(fmt.Sprintf("<p><strong>更新：</strong><span style=\"color:#e11d48;\">%s</span></p>", rec.Remarks))
		}
		if rec.Actor != "" {
			descBuilder.WriteString(fmt.Sprintf("<p><strong>主演：</strong>%s</p>", rec.Actor))
		}
		if rec.Director != "" {
			descBuilder.WriteString(fmt.Sprintf("<p><strong>导演：</strong>%s</p>", rec.Director))
		}
		if rec.Area != "" || rec.Year != "" || rec.Language != "" {
			descBuilder.WriteString(fmt.Sprintf("<p><strong>地区/年代/语言：</strong>%s / %s / %s</p>", rec.Area, rec.Year, rec.Language))
		}
		if len(rec.PlayGroups) > 0 {
			var groupInfo []string
			for _, g := range rec.PlayGroups {
				code := g.PlayerCode
				if code == "" {
					code = "在线播放"
				}
				groupInfo = append(groupInfo, fmt.Sprintf("%s (%d集)", code, len(g.Episodes)))
			}
			descBuilder.WriteString(fmt.Sprintf("<p><strong>播放源：</strong>%s</p>", strings.Join(groupInfo, " | ")))
		}
		if rec.Content != "" {
			descBuilder.WriteString(fmt.Sprintf("<p><strong>简介：</strong>%s</p>", rec.Content))
		}
		descBuilder.WriteString(fmt.Sprintf("<p><a href=\"%s\" target=\"_blank\" style=\"display:inline-block;padding:6px 14px;background:#4f46e5;color:#fff;text-decoration:none;border-radius:6px;font-size:13px;\">立即在线观看 &rarr;</a></p>", detailURL))
		descBuilder.WriteString("</div>")

		item := RSSItem{
			Title: CDATAText{Text: titleText},
			Link:  detailURL,
			GUID: RSSGUID{
				IsPermaLink: true,
				Value:       detailURL,
			},
			Category:    CDATAText{Text: rec.TypeName},
			PubDate:     rec.UpdatedAt.Format(time.RFC1123Z),
			Description: CDATAText{Text: descBuilder.String()},
		}

		if rec.Picture != "" {
			item.Enclosure = &RSSEnclosure{
				URL:    rec.Picture,
				Type:   "image/jpeg",
				Length: 0,
			}
		}

		items = append(items, item)
	}

	feed := RSSFeed{
		Version: "2.0",
		AtomNS:  "http://www.w3.org/2005/Atom",
		Channel: RSSChannel{
			Title:         channelTitle,
			Link:          baseURL + "/",
			Description:   siteDesc,
			Language:      "zh-CN",
			PubDate:       nowStr,
			LastBuildDate: lastBuildDate,
			Generator:     "Antigravity Video RSS Engine v2.0",
			AtomLink: AtomLink{
				Href: selfURL,
				Rel:  "self",
				Type: "application/rss+xml",
			},
			Items: items,
		},
	}

	// 7. 输出 XML
	w.Header().Set("Content-Type", "application/rss+xml; charset=utf-8")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.WriteHeader(http.StatusOK)

	_, _ = w.Write([]byte(xml.Header))
	enc := xml.NewEncoder(w)
	enc.Indent("", "  ")
	_ = enc.Encode(feed)
}
