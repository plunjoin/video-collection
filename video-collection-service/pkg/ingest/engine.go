// Package ingest implements bounded, content-neutral collection pipelines.
package ingest

import (
	"bytes"
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/PuerkitoBio/goquery"
	"github.com/andybalholm/cascadia"
	"video-collection-service/config"
)

type Sample struct {
	Raw    map[string]string `json:"raw"`
	Values map[string]string `json:"values"`
	Errors []string          `json:"errors"`
}

var fieldName = regexp.MustCompile(`^[a-zA-Z_][a-zA-Z0-9_]{0,63}$`)
var envName = regexp.MustCompile(`^[A-Z_][A-Z0-9_]*$`)

func Validate(src config.SourceConfig) error {
	p := src.Filter.Pipeline
	if src.Type != "pipeline" || p == nil || p.Version != 1 {
		return fmt.Errorf("需要 version=1 的通用采集规则")
	}
	if p.Target != "record" && p.Target != "article" && p.Target != "video" {
		return fmt.Errorf("请选择通用数据、文章或视频")
	}
	if p.Duplicate != "update" && p.Duplicate != "skip" {
		return fmt.Errorf("请选择重复记录更新或跳过")
	}
	if p.MaxRecords < 1 || p.MaxRecords > 10000 {
		return fmt.Errorf("单次记录上限须为 1–10000")
	}
	if src.PageLimit < 1 || src.PageLimit > 100 || src.TimeoutSec < 1 || src.TimeoutSec > 60 || src.IntervalMs < 0 || src.IntervalMs > 10000 || src.RetryCount < 0 || src.RetryCount > 3 {
		return fmt.Errorf("页数 1–100、超时 1–60 秒、间隔 0–10000 毫秒、重试 0–3 次")
	}
	if len(p.Fields) == 0 || len(p.Fields) > 100 {
		return fmt.Errorf("请配置 1–100 个字段")
	}
	seen := map[string]bool{}
	for _, f := range p.Fields {
		if !fieldName.MatchString(f.Target) || seen[f.Target] {
			return fmt.Errorf("字段名 %q 不合法或重复（使用字母、数字、下划线）", f.Target)
		}
		seen[f.Target] = true
		if f.Pattern != "" {
			if _, err := regexp.Compile(f.Pattern); err != nil {
				return fmt.Errorf("字段 %s 正则无效: %w", f.Target, err)
			}
		}
		if p.Input == "html" && f.Selector != "" && f.Selector != "$url" {
			if _, err := cascadia.Compile(f.Selector); err != nil {
				return fmt.Errorf("字段 %s CSS 无效: %w", f.Target, err)
			}
		}
	}
	if !seen[p.KeyField] {
		return fmt.Errorf("去重字段必须是已配置的目标字段")
	}
	if p.Target != "record" && !seen["title"] {
		return fmt.Errorf("文章和视频必须映射 title 字段")
	}
	if p.Target == "article" && !seen["content"] {
		return fmt.Errorf("文章必须映射 content 字段")
	}
	switch p.Input {
	case "api", "rss", "html":
		if err := validURL(src.API); err != nil {
			return err
		}
		if p.Request.Method == "" {
			p.Request.Method = "GET"
		}
		if p.Request.Method != "GET" && p.Request.Method != "POST" {
			return fmt.Errorf("仅支持 GET 或 POST 请求")
		}
		if p.Request.StartPage < 1 {
			p.Request.StartPage = 1
		}
		if p.Input == "html" {
			if p.HTML.ItemSelector == "" {
				return fmt.Errorf("请填写列表条目的 CSS 选择器")
			}
			for _, sel := range []string{p.HTML.ItemSelector, p.HTML.DetailSelector, p.HTML.NextSelector} {
				if sel != "" {
					if _, err := cascadia.Compile(sel); err != nil {
						return fmt.Errorf("CSS 选择器无效: %w", err)
					}
				}
			}
		}
	case "database":
		if !envName.MatchString(p.Database.DSNEnv) {
			return fmt.Errorf("请填写服务端连接串环境变量名，例如 IMPORT_DATABASE_DSN")
		}
		switch p.Database.Driver {
		case "postgres", "mysql", "sqlite", "sqlserver":
		default:
			return fmt.Errorf("不支持的数据库驱动")
		}
		if err := validateQuery(p.Database.Query); err != nil {
			return err
		}
	case "file":
		if !fileToken.MatchString(p.File.Token) {
			return fmt.Errorf("请先上传 .xlsx 或 UTF-8 .csv 文件")
		}
		if p.File.HeaderRow < 1 || p.File.HeaderRow > 100 {
			return fmt.Errorf("表头行须为 1–100")
		}
	default:
		return fmt.Errorf("未知数据源类型")
	}
	return nil
}

func validURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil {
		return fmt.Errorf("请输入不含用户名密码的 HTTP(S) 地址")
	}
	return nil
}

func stringValue(v any) string {
	if v == nil {
		return ""
	}
	if s, ok := v.(string); ok {
		return s
	}
	b, _ := json.Marshal(v)
	return string(b)
}

func pathValue(v any, path string) any {
	if path == "" || path == "$" {
		return v
	}
	path = strings.TrimPrefix(path, "$.")
	for _, key := range strings.Split(path, ".") {
		switch obj := v.(type) {
		case map[string]any:
			v = obj[key]
		case []any:
			i, err := strconv.Atoi(key)
			if err != nil || i < 0 || i >= len(obj) {
				return nil
			}
			v = obj[i]
		default:
			return nil
		}
	}
	return v
}

func MapRecord(p *config.PipelineRule, raw map[string]string) Sample {
	s := Sample{Raw: raw, Values: map[string]string{}, Errors: []string{}}
	for _, f := range p.Fields {
		v := raw[f.Target]
		if strings.TrimSpace(v) == "" {
			v = f.Default
		}
		if f.StripHTML {
			if doc, err := goquery.NewDocumentFromReader(strings.NewReader(v)); err == nil {
				doc.Find("script,style").Remove()
				v = doc.Text()
			}
		}
		if f.Pattern != "" {
			if re, err := regexp.Compile(f.Pattern); err == nil {
				v = re.ReplaceAllString(v, f.Replacement)
			}
		}
		if f.Trim {
			v = strings.TrimSpace(v)
		}
		if f.Required && strings.TrimSpace(v) == "" {
			s.Errors = append(s.Errors, f.Target+": 必填字段为空")
		}
		s.Values[f.Target] = v
	}
	for _, key := range []string{p.KeyField, requiredTitle(p.Target), requiredContent(p.Target)} {
		if key != "" && strings.TrimSpace(s.Values[key]) == "" {
			s.Errors = append(s.Errors, key+": 入库所需字段为空")
		}
	}
	return s
}

func requiredTitle(target string) string {
	if target != "record" {
		return "title"
	}
	return ""
}
func requiredContent(target string) string {
	if target == "article" {
		return "content"
	}
	return ""
}

// Run emits rows in order; preview uses the same extraction and cleaning path.
// Errors stop the run, while row validation failures are returned on each sample.
func Run(ctx context.Context, src config.SourceConfig, limit int, emit func(Sample) error) error {
	if err := Validate(src); err != nil {
		return err
	}
	p := src.Filter.Pipeline
	if limit <= 0 || limit > p.MaxRecords {
		limit = p.MaxRecords
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()
	switch p.Input {
	case "database":
		return databaseRows(ctx, p, limit, emit)
	case "file":
		return fileRows(ctx, p, limit, emit)
	}
	client := &http.Client{Timeout: time.Duration(src.TimeoutSec) * time.Second}
	client.CheckRedirect = func(req *http.Request, via []*http.Request) error {
		if len(via) >= 5 {
			return fmt.Errorf("重定向次数过多")
		}
		if req.URL.Host != via[0].URL.Host {
			return fmt.Errorf("不允许跨主机重定向，请直接填写目标地址")
		}
		return validURL(req.URL.String())
	}
	count := 0
	next := src.API
	visited := map[string]bool{}
	for page := 0; page < src.PageLimit && count < limit; page++ {
		u, _ := url.Parse(next)
		q := u.Query()
		for k, v := range src.CustomParams {
			if strings.Contains(v, "{hours}") {
				if src.CollectHours > 0 {
					q.Set(k, strings.ReplaceAll(v, "{hours}", strconv.Itoa(src.CollectHours)))
				}
			} else if strings.Contains(v, "{page}") {
				q.Set(k, strings.ReplaceAll(v, "{page}", strconv.Itoa(p.Request.StartPage+page)))
			} else {
				q.Set(k, v)
			}
		}
		if p.Request.PageParam != "" && (p.Input == "api" || p.Input == "rss" || p.HTML.NextSelector == "") {
			q.Set(p.Request.PageParam, strconv.Itoa(p.Request.StartPage+page))
		}
		u.RawQuery = q.Encode()
		if visited[u.String()] {
			break
		}
		visited[u.String()] = true
		body, err := fetch(ctx, client, src, u.String(), page > 0)
		if err != nil {
			return err
		}
		before := count
		if p.Input == "api" || p.Input == "rss" {
			var list []any
			if p.Input == "rss" || isXMLPayload(body) {
				items, err := parseFeed(body)
				if err != nil {
					return err
				}
				list = items
			} else {
				var root any
				dec := json.NewDecoder(strings.NewReader(string(body)))
				dec.UseNumber()
				if err := dec.Decode(&root); err != nil {
					if items, xmlErr := parseFeed(body); xmlErr == nil && len(items) > 0 {
						list = items
					} else {
						return fmt.Errorf("接口响应不是有效 JSON 或 RSS/XML 数据源")
					}
				} else {
					arr, ok := pathValue(root, p.Request.ListPath).([]any)
					if !ok {
						return fmt.Errorf("列表路径 %q 未指向数组", p.Request.ListPath)
					}
					list = arr
				}
			}
			for _, obj := range list {
				if count >= limit {
					break
				}
				raw := map[string]string{}
				for _, f := range p.Fields {
					if f.Selector != "" {
						raw[f.Target] = stringValue(pathValue(obj, f.Selector))
					}
				}
				if err := emit(MapRecord(p, raw)); err != nil {
					return err
				}
				count++
			}
			if p.Request.PageParam == "" {
				break
			}
		} else {
			doc, err := goquery.NewDocumentFromReader(strings.NewReader(string(body)))
			if err != nil {
				return err
			}
			items := doc.Find(p.HTML.ItemSelector)
			for i := 0; i < items.Length() && count < limit; i++ {
				item := items.Eq(i)
				base := u
				if p.HTML.DetailSelector != "" {
					link := item.Find(p.HTML.DetailSelector).First()
					if item.Is(p.HTML.DetailSelector) {
						link = item
					}
					href, ok := link.Attr("href")
					if !ok {
						return fmt.Errorf("第 %d 条记录未匹配详情链接", count+1)
					}
					ref, err := url.Parse(href)
					if err != nil {
						return fmt.Errorf("详情链接无效")
					}
					base = u.ResolveReference(ref)
					if base.Host != u.Host {
						return fmt.Errorf("详情链接必须与列表同主机")
					}
					data, err := fetch(ctx, client, src, base.String(), true)
					if err != nil {
						return err
					}
					detail, err := goquery.NewDocumentFromReader(strings.NewReader(string(data)))
					if err != nil {
						return err
					}
					item = detail.Selection
				}
				raw := map[string]string{}
				for _, f := range p.Fields {
					if f.Selector == "$url" {
						raw[f.Target] = base.String()
						continue
					}
					if f.Selector == "" {
						continue
					}
					sel := item.Find(f.Selector).First()
					if item.Is(f.Selector) {
						sel = item
					}
					v := ""
					switch f.Attribute {
					case "", "text":
						v = sel.Text()
					case "html":
						v, _ = sel.Html()
					default:
						v, _ = sel.Attr(f.Attribute)
					}
					if (f.Attribute == "href" || f.Attribute == "src") && v != "" {
						if ref, err := url.Parse(v); err == nil {
							v = base.ResolveReference(ref).String()
						}
					}
					raw[f.Target] = v
				}
				if err := emit(MapRecord(p, raw)); err != nil {
					return err
				}
				count++
			}
			if p.HTML.NextSelector != "" {
				href, ok := doc.Find(p.HTML.NextSelector).First().Attr("href")
				if !ok || href == "" {
					break
				}
				ref, err := url.Parse(href)
				if err != nil {
					return fmt.Errorf("下一页链接无效")
				}
				target := u.ResolveReference(ref)
				if target.Host != u.Host {
					return fmt.Errorf("下一页必须与列表同主机")
				}
				next = target.String()
			} else if p.Request.PageParam == "" {
				break
			}
		}
		if count == before {
			break
		}
	}
	return nil
}

func fetch(ctx context.Context, client *http.Client, src config.SourceConfig, address string, pause bool) ([]byte, error) {
	if err := validURL(address); err != nil {
		return nil, err
	}
	var last error
	for attempt := 0; attempt <= src.RetryCount; attempt++ {
		if pause || attempt > 0 {
			timer := time.NewTimer(time.Duration(src.IntervalMs) * time.Millisecond)
			select {
			case <-ctx.Done():
				timer.Stop()
				return nil, ctx.Err()
			case <-timer.C:
			}
		}
		method, body := src.Filter.Pipeline.Request.Method, src.Filter.Pipeline.Request.Body
		if src.Filter.Pipeline.Input == "html" || src.Filter.Pipeline.Input == "rss" {
			method, body = "GET", ""
		}
		req, err := http.NewRequestWithContext(ctx, method, address, strings.NewReader(body))
		if err != nil {
			return nil, fmt.Errorf("请求配置无效")
		}
		for k, v := range src.Headers {
			req.Header.Set(k, v)
		}
		if method == "POST" && req.Header.Get("Content-Type") == "" {
			req.Header.Set("Content-Type", "application/json")
		}
		res, err := client.Do(req)
		if err != nil {
			last = fmt.Errorf("请求失败，请检查地址、网络和超时配置")
			continue
		}
		data, readErr := io.ReadAll(io.LimitReader(res.Body, 8*1024*1024+1))
		res.Body.Close()
		if res.StatusCode < 200 || res.StatusCode >= 300 {
			last = fmt.Errorf("上游返回 HTTP %d", res.StatusCode)
			continue
		}
		if readErr != nil {
			last = fmt.Errorf("读取上游响应失败")
			continue
		}
		if len(data) > 8*1024*1024 {
			return nil, fmt.Errorf("单次响应超过 8 MB 上限")
		}
		return data, nil
	}
	return nil, last
}

func isXMLPayload(body []byte) bool {
	trimmed := strings.TrimSpace(string(body))
	return strings.HasPrefix(trimmed, "<?xml") ||
		strings.HasPrefix(trimmed, "<rss") ||
		strings.HasPrefix(trimmed, "<feed") ||
		strings.HasPrefix(trimmed, "<RDF") ||
		strings.HasPrefix(trimmed, "<channel") ||
		(strings.HasPrefix(trimmed, "<!DOCTYPE") && (strings.Contains(trimmed, "<rss") || strings.Contains(trimmed, "<feed")))
}

var imgRegex = regexp.MustCompile(`(?i)<img[^>]+src=["']([^"']+)["']`)

func extractCover(candidates ...string) string {
	for _, c := range candidates {
		c = strings.TrimSpace(c)
		if strings.HasPrefix(c, "http://") || strings.HasPrefix(c, "https://") {
			return c
		}
	}
	for _, text := range candidates {
		if text != "" {
			if m := imgRegex.FindStringSubmatch(text); len(m) > 1 {
				return m[1]
			}
		}
	}
	return ""
}

type rssItem struct {
	Title          string `xml:"title"`
	Link           string `xml:"link"`
	GUID           string `xml:"guid"`
	Description    string `xml:"description"`
	ContentEncoded string `xml:"encoded"`
	PubDate        string `xml:"pubDate"`
	Creator        string `xml:"creator"`
	Author         string `xml:"author"`
	Category       string `xml:"category"`
	Enclosure      struct {
		URL string `xml:"url,attr"`
	} `xml:"enclosure"`
	MediaThumbnail struct {
		URL string `xml:"url,attr"`
	} `xml:"thumbnail"`
	MediaContent struct {
		URL string `xml:"url,attr"`
	} `xml:"content"`
}

type rssFeed struct {
	XMLName xml.Name `xml:"rss"`
	Channel struct {
		Title       string    `xml:"title"`
		Link        string    `xml:"link"`
		Description string    `xml:"description"`
		Items       []rssItem `xml:"item"`
	} `xml:"channel"`
}

type atomFeed struct {
	XMLName xml.Name    `xml:"feed"`
	Title   string      `xml:"title"`
	Entries []atomEntry `xml:"entry"`
}

type atomEntry struct {
	Title     string     `xml:"title"`
	ID        string     `xml:"id"`
	Published string     `xml:"published"`
	Updated   string     `xml:"updated"`
	Summary   string     `xml:"summary"`
	Content   string     `xml:"content"`
	Links     []atomLink `xml:"link"`
	Author    struct {
		Name string `xml:"name"`
	} `xml:"author"`
	Category struct {
		Term string `xml:"term,attr"`
	} `xml:"category"`
}

type atomLink struct {
	Rel  string `xml:"rel,attr"`
	Href string `xml:"href,attr"`
}

type channelFeed struct {
	XMLName xml.Name  `xml:"channel"`
	Items   []rssItem `xml:"item"`
}

type rdfFeed struct {
	XMLName xml.Name  `xml:"RDF"`
	Items   []rssItem `xml:"item"`
}

type maccmsXMLFeed struct {
	Videos []struct {
		ID       string `xml:"id"`
		Name     string `xml:"name"`
		Type     string `xml:"type"`
		Pic      string `xml:"pic"`
		Actor    string `xml:"actor"`
		Director string `xml:"director"`
		Des      string `xml:"des"`
		Year     string `xml:"year"`
		Area     string `xml:"area"`
		Note     string `xml:"note"`
		DL       struct {
			DD []struct {
				Flag string `xml:"flag,attr"`
				Data string `xml:",chardata"`
			} `xml:"dd"`
		} `xml:"dl"`
	} `xml:"list>video"`
}

func rssItemToMap(item rssItem) map[string]any {
	link := strings.TrimSpace(item.Link)
	guid := strings.TrimSpace(item.GUID)
	id := guid
	if id == "" {
		id = link
	}
	if link == "" {
		link = guid
	}
	content := strings.TrimSpace(item.ContentEncoded)
	if content == "" {
		content = strings.TrimSpace(item.Description)
	}
	desc := strings.TrimSpace(item.Description)
	if desc == "" {
		desc = content
	}
	author := strings.TrimSpace(item.Creator)
	if author == "" {
		author = strings.TrimSpace(item.Author)
	}
	cover := extractCover(item.Enclosure.URL, item.MediaContent.URL, item.MediaThumbnail.URL, item.ContentEncoded, item.Description)

	return map[string]any{
		"id":           id,
		"guid":         guid,
		"link":         link,
		"url":          link,
		"title":        strings.TrimSpace(item.Title),
		"description":  desc,
		"summary":      desc,
		"content":      content,
		"author":       author,
		"creator":      author,
		"pubDate":      strings.TrimSpace(item.PubDate),
		"pub_date":     strings.TrimSpace(item.PubDate),
		"published_at": strings.TrimSpace(item.PubDate),
		"category":     strings.TrimSpace(item.Category),
		"cover":        cover,
	}
}

func atomEntryToMap(entry atomEntry) map[string]any {
	var link string
	for _, l := range entry.Links {
		if l.Rel == "" || l.Rel == "alternate" {
			link = strings.TrimSpace(l.Href)
			break
		}
	}
	if link == "" && len(entry.Links) > 0 {
		link = strings.TrimSpace(entry.Links[0].Href)
	}
	id := strings.TrimSpace(entry.ID)
	if id == "" {
		id = link
	}
	if link == "" {
		link = id
	}
	content := strings.TrimSpace(entry.Content)
	if content == "" {
		content = strings.TrimSpace(entry.Summary)
	}
	summary := strings.TrimSpace(entry.Summary)
	if summary == "" {
		summary = content
	}
	pubDate := strings.TrimSpace(entry.Published)
	if pubDate == "" {
		pubDate = strings.TrimSpace(entry.Updated)
	}
	author := strings.TrimSpace(entry.Author.Name)
	cover := extractCover(entry.Content, entry.Summary)

	return map[string]any{
		"id":           id,
		"guid":         id,
		"link":         link,
		"url":          link,
		"title":        strings.TrimSpace(entry.Title),
		"description":  summary,
		"summary":      summary,
		"content":      content,
		"author":       author,
		"creator":      author,
		"pubDate":      pubDate,
		"pub_date":     pubDate,
		"published_at": pubDate,
		"category":     strings.TrimSpace(entry.Category.Term),
		"cover":        cover,
	}
}

func parseFeed(body []byte) ([]any, error) {
	clean := bytes.TrimPrefix(body, []byte("\xef\xbb\xbf"))
	clean = bytes.TrimSpace(clean)

	var rss rssFeed
	if err := xml.Unmarshal(clean, &rss); err == nil && len(rss.Channel.Items) > 0 {
		var list []any
		for _, item := range rss.Channel.Items {
			list = append(list, rssItemToMap(item))
		}
		return list, nil
	}

	var atom atomFeed
	if err := xml.Unmarshal(clean, &atom); err == nil && len(atom.Entries) > 0 {
		var list []any
		for _, entry := range atom.Entries {
			list = append(list, atomEntryToMap(entry))
		}
		return list, nil
	}

	var ch channelFeed
	if err := xml.Unmarshal(clean, &ch); err == nil && len(ch.Items) > 0 {
		var list []any
		for _, item := range ch.Items {
			list = append(list, rssItemToMap(item))
		}
		return list, nil
	}

	var rdf rdfFeed
	if err := xml.Unmarshal(clean, &rdf); err == nil && len(rdf.Items) > 0 {
		var list []any
		for _, item := range rdf.Items {
			list = append(list, rssItemToMap(item))
		}
		return list, nil
	}

	var mac maccmsXMLFeed
	if err := xml.Unmarshal(clean, &mac); err == nil && len(mac.Videos) > 0 {
		var list []any
		for _, v := range mac.Videos {
			var playURLs []string
			var playFroms []string
			for _, dd := range v.DL.DD {
				if strings.TrimSpace(dd.Data) != "" {
					flag := dd.Flag
					if flag == "" {
						flag = "m3u8"
					}
					playFroms = append(playFroms, flag)
					playURLs = append(playURLs, strings.TrimSpace(dd.Data))
				}
			}
			list = append(list, map[string]any{
				"id":          v.ID,
				"title":       v.Name,
				"name":        v.Name,
				"category":    v.Type,
				"type":        v.Type,
				"cover":       v.Pic,
				"pic":         v.Pic,
				"actor":       v.Actor,
				"director":    v.Director,
				"content":     v.Des,
				"description": v.Des,
				"year":        v.Year,
				"area":        v.Area,
				"remarks":     v.Note,
				"play_url":    strings.Join(playURLs, "$$$"),
				"play_from":   strings.Join(playFroms, "$$$"),
			})
		}
		return list, nil
	}

	return nil, fmt.Errorf("未识别到有效的 RSS、Atom 或 XML 数据条目")
}

