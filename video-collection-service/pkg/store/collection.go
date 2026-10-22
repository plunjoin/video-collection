package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"video-collection-service/pkg/collector"
)

type CollectionRecord struct {
	SourceID  string            `json:"source_id"`
	Target    string            `json:"target"`
	Key       string            `json:"key"`
	Values    map[string]string `json:"values"`
	ContentID int               `json:"content_id"`
	UpdatedAt string            `json:"updated_at"`
}

type CollectionStore interface {
	SaveCollectionRecord(context.Context, CollectionRecord, bool) (bool, error)
	ListCollectionRecords(context.Context, string, int, int) ([]CollectionRecord, int, error)
	HasCollectionRecord(context.Context, string, string, string) (bool, error)
	UpdateCollectionRecord(ctx context.Context, sourceID, target, key string, values map[string]string) error
	DeleteCollectionRecord(ctx context.Context, sourceID, target, key string) error
	RectifyCollectionRecordToWiki(ctx context.Context, sourceID, target, key string, subject WikiSubject) (*WikiSubject, error)
	RectifyCollectionRecordToVideo(ctx context.Context, sourceID, target, key string, vod *collector.CleanedVod) (int, error)
	BatchRectifyCollectionRecords(ctx context.Context, sourceID, target string) (int, error)
	ImportSampleCollectionRecords(ctx context.Context, sourceID, target string) (int, error)
}

func (s *SQLContentStore) HasCollectionRecord(ctx context.Context, source, target, key string) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM collection_records WHERE source_id=$1 AND target=$2 AND record_key=$3`, source, target, key).Scan(&n)
	return n > 0, err
}

// Article and provenance are committed together. Reimports update drafts only;
// a published/hidden editorial decision is never silently overwritten.
func (s *SQLContentStore) SaveCollectionRecord(ctx context.Context, r CollectionRecord, skip bool) (bool, error) {
	if r.SourceID == "" || r.Key == "" {
		return false, fmt.Errorf("记录缺少来源或唯一标识")
	}
	b, err := s.GetBusinessType(ctx, r.Target)
	if err != nil {
		return false, fmt.Errorf("未知业务类型 %q: %w", r.Target, err)
	}
	if _, err = ValidateBusinessValues(b, r.Values); err != nil {
		return false, err
	}
	data, err := json.Marshal(r.Values)
	if err != nil {
		return false, err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	var id int
	err = tx.QueryRowContext(ctx, `SELECT content_id FROM collection_records WHERE source_id=$1 AND target=$2 AND record_key=$3`, r.SourceID, r.Target, r.Key).Scan(&id)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return false, err
	}
	if err == nil && skip {
		return false, nil
	}
	if b.Writer == "table" {
		r.ContentID, err = upsertBusinessRow(ctx, tx, b, r)
		if err != nil {
			return false, err
		}
	}
	if b.Writer == "article" {
		if id > 0 {
			var status string
			err = tx.QueryRowContext(ctx, `SELECT status FROM content_entries WHERE id=$1 AND kind='news'`, id).Scan(&status)
			if errors.Is(err, sql.ErrNoRows) {
				id = 0
			} else if err != nil {
				return false, err
			} else if status != "draft" {
				return false, nil
			}
		}
		now := time.Now().UTC()
		summary := r.Values["summary"]
		if strings.TrimSpace(summary) == "" && r.Values["content"] != "" {
			runes := []rune(r.Values["content"])
			if len(runes) > 150 {
				summary = string(runes[:150]) + "..."
			} else {
				summary = string(runes)
			}
		}
		initialStatus := "draft"
		if s, ok := r.Values["status"]; ok && (s == "published" || s == "draft") {
			initialStatus = s
		}
		sourceURL := strings.TrimSpace(r.Values["url"])
		sourceName := strings.TrimSpace(r.Values["source_name"])
		if sourceName == "" {
			sourceName = strings.TrimSpace(r.Values["source_label"])
		}
		if sourceName == "" {
			sourceName = strings.TrimSpace(r.Values["source"])
		}
		publishedAt := strings.TrimSpace(r.Values["published_at"])
		publishedTime, validPublishedTime := parseCollectionPublishedAt(publishedAt)
		if id == 0 {
			createdAt := now
			if validPublishedTime {
				createdAt = publishedTime
			}
			var author int
			if err = tx.QueryRowContext(ctx, `SELECT id FROM users WHERE role IN ('admin','super_admin') AND status=1 ORDER BY id LIMIT 1`).Scan(&author); err != nil {
				return false, fmt.Errorf("没有可用的管理员作为文章作者")
			}
			err = tx.QueryRowContext(ctx, `INSERT INTO content_entries(kind,author_id,title,summary,content,cover,category,source_url,source_name,published_at,status,created_at,updated_at) VALUES ('news',$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`, author, r.Values["title"], summary, r.Values["content"], r.Values["cover"], r.Values["category"], sourceURL, sourceName, publishedAt, initialStatus, createdAt, now).Scan(&id)
		} else {
			_, err = tx.ExecContext(ctx, `UPDATE content_entries SET title=$1,summary=$2,content=$3,cover=$4,category=$5,source_url=$6,source_name=$7,published_at=$8,updated_at=$9,created_at=COALESCE($10,created_at) WHERE id=$11 AND status='draft'`, r.Values["title"], summary, r.Values["content"], r.Values["cover"], r.Values["category"], sourceURL, sourceName, publishedAt, now, sql.NullTime{Time: publishedTime, Valid: validPublishedTime}, id)
		}
		if err != nil {
			return false, err
		}
		r.ContentID = id
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO collection_records(source_id,target,record_key,payload,content_id,updated_at) VALUES ($1,$2,$3,$4,$5,$6)
 ON CONFLICT(source_id,target,record_key) DO UPDATE SET payload=excluded.payload,content_id=excluded.content_id,updated_at=excluded.updated_at`, r.SourceID, r.Target, r.Key, string(data), r.ContentID, time.Now().UTC().Format(time.RFC3339Nano))
	if err != nil {
		return false, err
	}
	if err = tx.Commit(); err != nil {
		return false, err
	}
	if r.Target == "article" && r.ContentID > 0 {
		notifyRAGContentIngest(ctx, "news", r.ContentID)
	}
	return true, nil
}

func parseCollectionPublishedAt(raw string) (time.Time, bool) {
	// RFC3339Nano also accepts RFC3339. Timestamps without a zone use UTC.
	for _, layout := range []string{
		time.RFC3339Nano,
		"2006-01-02T15:04:05Z0700",
		"2006-01-02 15:04:05Z07:00",
		"2006-01-02 15:04:05Z0700",
		"2006-01-02T15:04:05",
		time.DateTime,
		"2006-01-02 15:04",
		time.DateOnly,
		time.RFC1123Z,
		time.RFC1123,
	} {
		if parsed, err := time.Parse(layout, raw); err == nil {
			return parsed.UTC(), true
		}
	}
	return time.Time{}, false
}

func (s *SQLContentStore) ListCollectionRecords(ctx context.Context, source string, page, size int) ([]CollectionRecord, int, error) {
	size, offset := contentPage(page, size)
	var total int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM collection_records WHERE source_id=$1`, source).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.QueryContext(ctx, `SELECT source_id,target,record_key,payload,content_id,updated_at FROM collection_records WHERE source_id=$1 ORDER BY updated_at DESC,record_key LIMIT $2 OFFSET $3`, source, size, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	result := []CollectionRecord{}
	for rows.Next() {
		var r CollectionRecord
		var payload string
		if err := rows.Scan(&r.SourceID, &r.Target, &r.Key, &payload, &r.ContentID, &r.UpdatedAt); err != nil {
			return nil, 0, err
		}
		if err := json.Unmarshal([]byte(payload), &r.Values); err != nil {
			return nil, 0, err
		}
		result = append(result, r)
	}
	return result, total, rows.Err()
}

func (s *SQLContentStore) UpdateCollectionRecord(ctx context.Context, sourceID, target, key string, values map[string]string) error {
	if sourceID == "" || key == "" {
		return fmt.Errorf("记录缺少来源或唯一标识")
	}
	b, err := s.GetBusinessType(ctx, target)
	if err != nil {
		return err
	}
	if b.Writer == "table" {
		exists, err := s.HasCollectionRecord(ctx, sourceID, target, key)
		if err != nil {
			return err
		}
		if !exists {
			return fmt.Errorf("未找到对应采集记录")
		}
		_, err = s.SaveCollectionRecord(ctx, CollectionRecord{SourceID: sourceID, Target: target, Key: key, Values: values}, false)
		return err
	}

	data, err := json.Marshal(values)
	if err != nil {
		return err
	}
	res, err := s.db.ExecContext(ctx, `UPDATE collection_records SET payload=$1, updated_at=$2 WHERE source_id=$3 AND target=$4 AND record_key=$5`,
		string(data), time.Now().UTC().Format(time.RFC3339Nano), sourceID, target, key)
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err == nil && affected == 0 {
		return fmt.Errorf("未找到对应采集记录")
	}
	return err
}

func (s *SQLContentStore) DeleteCollectionRecord(ctx context.Context, sourceID, target, key string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	b, err := getBusinessType(ctx, tx, target)
	if err != nil {
		return err
	}
	if b.Writer == "table" {
		if _, err = tx.ExecContext(ctx, "DELETE FROM "+quoteIdent(b.TableName)+" WHERE id=(SELECT content_id FROM collection_records WHERE source_id=$1 AND target=$2 AND record_key=$3)", sourceID, target, key); err != nil {
			return err
		}
	}
	res, err := tx.ExecContext(ctx, `DELETE FROM collection_records WHERE source_id=$1 AND target=$2 AND record_key=$3`, sourceID, target, key)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("未找到对应采集记录")
	}
	return tx.Commit()
}

func (s *SQLContentStore) RectifyCollectionRecordToWiki(ctx context.Context, sourceID, target, key string, subject WikiSubject) (*WikiSubject, error) {
	if strings.TrimSpace(subject.Name) == "" {
		return nil, fmt.Errorf("词条主名称不能为空")
	}
	if subject.Type == "" {
		subject.Type = "person"
	}
	var subID int
	if subject.ID > 0 {
		if err := s.UpdateWikiSubject(ctx, &subject); err != nil {
			return nil, err
		}
		subID = subject.ID
	} else {
		// 检查同名词条
		existing, err := s.GetWikiSubjectByName(ctx, subject.Name)
		if err == nil && existing != nil {
			subject.ID = existing.ID
			if err := s.UpdateWikiSubject(ctx, &subject); err != nil {
				return nil, err
			}
			subID = existing.ID
		} else {
			id, err := s.CreateWikiSubject(ctx, &subject)
			if err != nil {
				return nil, err
			}
			subID = id
			subject.ID = id
		}
	}

	// 关联到采集记录的 content_id
	nowStr := time.Now().UTC().Format(time.RFC3339Nano)
	_, _ = s.db.ExecContext(ctx, `UPDATE collection_records SET content_id=$1, updated_at=$2 WHERE source_id=$3 AND target=$4 AND record_key=$5`,
		subID, nowStr, sourceID, target, key)

	return &subject, nil
}

func (s *SQLContentStore) RectifyCollectionRecordToVideo(ctx context.Context, sourceID, target, key string, vod *collector.CleanedVod) (int, error) {
	if vod == nil || strings.TrimSpace(vod.Name) == "" {
		return 0, fmt.Errorf("视频名称不能为空")
	}
	now := time.Now().UTC()
	var vid int
	err := s.db.QueryRowContext(ctx, `SELECT id FROM videos WHERE name = $1 LIMIT 1`, vod.Name).Scan(&vid)
	if err == nil && vid > 0 {
		_, err = s.db.ExecContext(ctx, `UPDATE videos SET picture=$1, actor=$2, director=$3, content=$4, area=$5, year=$6, type_name=$7, remarks=$8, updated_at=$9 WHERE id=$10`,
			vod.Picture, vod.Actor, vod.Director, vod.Content, vod.Area, vod.Year, vod.TargetTypeName, vod.Remarks, now, vid)
		if err != nil {
			return 0, err
		}
	} else {
		err = s.db.QueryRowContext(ctx, `INSERT INTO videos(name, sub_name, type_id, type_name, picture, actor, director, area, language, year, remarks, content, source_id, hits, created_at, updated_at)
			VALUES($1, '', 1, $2, $3, $4, $5, $6, '国语', $7, $8, $9, $10, 0, $11, $12) RETURNING id`,
			vod.Name, vod.TargetTypeName, vod.Picture, vod.Actor, vod.Director, vod.Area, vod.Year, vod.Remarks, vod.Content, sourceID, now, now).Scan(&vid)
		if err != nil {
			return 0, err
		}
	}

	// 如果有播放源或播放地址，写入/更新 play_sources 表
	if len(vod.PlayGroups) > 0 {
		for _, pg := range vod.PlayGroups {
			if len(pg.Episodes) == 0 {
				continue
			}
			epBytes, _ := json.Marshal(pg.Episodes)
			playerCode := pg.PlayerCode
			if playerCode == "" {
				playerCode = "m3u8"
			}
			server := pg.Server
			if server == "" {
				server = "no"
			}
			srcName := vod.SourceName
			if srcName == "" {
				srcName = pg.SourceName
			}
			var existingPlayID int
			_ = s.db.QueryRowContext(ctx, `SELECT id FROM play_sources WHERE video_id=$1 AND player_code=$2 LIMIT 1`, vid, playerCode).Scan(&existingPlayID)
			if existingPlayID > 0 {
				_, _ = s.db.ExecContext(ctx, `UPDATE play_sources SET source_id=$1, source_name=$2, server=$3, note=$4, episodes=$5, updated_at=$6 WHERE id=$7`,
					sourceID, srcName, server, pg.Note, string(epBytes), now, existingPlayID)
			} else {
				_, _ = s.db.ExecContext(ctx, `INSERT INTO play_sources (video_id, source_id, source_name, player_code, server, note, episodes, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
					vid, sourceID, srcName, playerCode, server, pg.Note, string(epBytes), now)
			}
		}
	}

	// 绑定到采集记录
	nowStr := now.Format(time.RFC3339Nano)
	_, _ = s.db.ExecContext(ctx, `UPDATE collection_records SET content_id=$1, updated_at=$2 WHERE source_id=$3 AND target=$4 AND record_key=$5`,
		vid, nowStr, sourceID, target, key)

	return vid, nil
}

func (s *SQLContentStore) ImportSampleCollectionRecords(ctx context.Context, sourceID, target string) (int, error) {
	if sourceID == "" {
		sourceID = "demo_rule"
	}
	if target == "" {
		target = "record"
	}

	samples := []CollectionRecord{
		{
			SourceID: sourceID,
			Target:   target,
			Key:      "tmdb_person_1892",
			Values: map[string]string{
				"actor_id":      "1892",
				"name":          "成龙",
				"original_name": "Jackie Chan",
				"gender":        "男",
				"popularity":    "98.5",
				"avatar":        "https://image.tmdb.org/t/p/w500/8qBuzBP0NiPTHgD9FO32G10U0.jpg",
				"known_for":     "警察故事 / 尖峰时刻 / 神话",
				"birthday":      "1954-04-07",
				"role_type":     "actor",
				"biography":     "大中华区传奇动作巨星、导演、武术指导，奥斯卡终身成就奖得主。",
			},
		},
		{
			SourceID: sourceID,
			Target:   target,
			Key:      "tmdb_person_12489",
			Values: map[string]string{
				"actor_id":      "12489",
				"name":          "高岩成二",
				"original_name": "Seiji Takaiwa",
				"gender":        "男",
				"popularity":    "85.2",
				"avatar":        "https://image.tmdb.org/t/p/w500/takaiwa_seiji.jpg",
				"known_for":     "假面骑士空我 / 极狐 / 电王 / 龙骑",
				"birthday":      "1968-11-03",
				"role_type":     "suit_actor",
				"biography":     "被誉为『平成假面骑士之父』的日本传奇皮套演员、动作特技监督，主演了平成时代绝大多数主骑皮套角色。",
			},
		},
		{
			SourceID: sourceID,
			Target:   target,
			Key:      "tmdb_person_6541",
			Values: map[string]string{
				"actor_id":      "6541",
				"name":          "神谷浩史",
				"original_name": "Hiroshi Kamiya",
				"gender":        "男",
				"popularity":    "91.0",
				"avatar":        "https://image.tmdb.org/t/p/w500/kamiya_hiroshi.jpg",
				"known_for":     "进击的巨人 (利威尔兵长) / 夏目友人帐",
				"birthday":      "1975-01-28",
				"role_type":     "cv",
				"biography":     "日本顶级男性声优、歌手。配音代表作有《进击的巨人》利威尔、《夏目友人帐》夏目贵志、《物语系列》阿良良木历等。",
			},
		},
		{
			SourceID: sourceID,
			Target:   target,
			Key:      "tmdb_person_7842",
			Values: map[string]string{
				"actor_id":      "7842",
				"name":          "庵野秀明",
				"original_name": "Hideaki Anno",
				"gender":        "男",
				"popularity":    "89.4",
				"avatar":        "https://image.tmdb.org/t/p/w500/anno_hideaki.jpg",
				"known_for":     "新世纪福音战士 / 新·假面骑士 / 新·哥斯拉",
				"birthday":      "1960-05-22",
				"role_type":     "director",
				"biography":     "日本著名动画与特摄导演、编剧，Khara 工作室创始人，代表作《新世纪福音战士》(EVA)。",
			},
		},
		{
			SourceID: sourceID,
			Target:   target,
			Key:      "tmdb_movie_9901",
			Values: map[string]string{
				"movie_id":      "9901",
				"title":         "假面骑士极狐",
				"name":          "假面骑士极狐",
				"original_name": "仮面ライダーギーツ",
				"popularity":    "95.6",
				"cover":         "https://image.tmdb.org/t/p/w500/geats_main_poster.jpg",
				"avatar":        "https://image.tmdb.org/t/p/w500/geats_main_poster.jpg",
				"release_date":  "2022-09-04",
				"category":      "特摄作品",
				"role_type":     "tokusatsu",
				"biography":     "令和假面骑士系列第4作，讲述愿望大奖赛（DGP）中不败白狐骑士浮世英寿的战斗物语。",
			},
		},
	}

	count := 0
	for _, rec := range samples {
		saved, err := s.SaveCollectionRecord(ctx, rec, false)
		if err == nil && saved {
			count++
		}
	}
	return count, nil
}

func (s *SQLContentStore) BatchRectifyCollectionRecords(ctx context.Context, sourceID, target string) (int, error) {
	query := `SELECT source_id, target, record_key, payload FROM collection_records WHERE (content_id = 0 OR content_id IS NULL)`
	var args []any
	if sourceID != "" {
		query += ` AND source_id = $1`
		args = append(args, sourceID)
		if target != "" {
			query += ` AND target = $2`
			args = append(args, target)
		}
	} else if target != "" {
		query += ` AND target = $1`
		args = append(args, target)
	}

	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	type pendingItem struct {
		srcID  string
		target string
		key    string
		vals   map[string]string
	}
	var items []pendingItem

	for rows.Next() {
		var src, tgt, key, payloadStr string
		if err := rows.Scan(&src, &tgt, &key, &payloadStr); err != nil {
			continue
		}
		var valMap map[string]string
		if err := json.Unmarshal([]byte(payloadStr), &valMap); err != nil || valMap == nil {
			continue
		}
		items = append(items, pendingItem{srcID: src, target: tgt, key: key, vals: valMap})
	}
	rows.Close()

	rectifiedCount := 0
	for _, item := range items {
		v := item.vals
		name := v["name"]
		if name == "" {
			name = v["title"]
		}
		if name == "" {
			name = item.key
		}

		// 判断是转入视频库还是 Wiki 实体
		isVideo := item.target == "video" || v["play_url"] != "" || v["vod_play_url"] != ""
		if isVideo {
			playURL := v["play_url"]
			if playURL == "" {
				playURL = v["vod_play_url"]
			}
			playFrom := v["play_from"]
			if playFrom == "" {
				playFrom = v["vod_play_from"]
			}
			if playFrom == "" {
				playFrom = "m3u8"
			}
			vod := collector.CleanedVod{
				SourceID:       item.srcID,
				SourceName:     item.srcID,
				Name:           name,
				SubName:        v["sub_name"],
				Picture:        v["cover"],
				Content:        v["content"],
				TargetTypeName: v["category"],
				Year:           v["year"],
				Actor:          v["actor"],
				Director:       v["director"],
				Area:           v["area"],
				Remarks:        v["remarks"],
			}
			if vod.Picture == "" {
				vod.Picture = v["vod_pic"]
			}
			if vod.Picture == "" {
				vod.Picture = v["picture"]
			}
			if vod.Content == "" {
				vod.Content = v["vod_content"]
			}
			if vod.Year == "" {
				vod.Year = v["release_date"]
			}
			if playURL != "" {
				groups := collector.ParsePlayGroups(playFrom, v["play_server"], v["play_note"], playURL)
				for i := range groups {
					if groups[i].SourceID == "" {
						groups[i].SourceID = item.srcID
					}
				}
				vod.PlayGroups = groups
			}
			if _, err := s.RectifyCollectionRecordToVideo(ctx, item.srcID, item.target, item.key, &vod); err == nil {
				rectifiedCount++
			}
		} else {
			// Wiki 实体 (人物或作品)
			subType := v["role_type"]
			isWork := v["movie_id"] != "" || v["title"] != ""
			entityType := "person"
			if isWork {
				entityType = "work"
				if subType == "" {
					subType = "movie"
				}
			} else {
				if subType == "" {
					subType = "actor"
				}
			}
			summary := v["biography"]
			if summary == "" {
				summary = v["overview"]
			}
			if summary == "" {
				summary = v["content"]
			}
			if summary == "" {
				summary = v["summary"]
			}
			cover := v["avatar"]
			if cover == "" {
				cover = v["cover"]
			}
			if cover == "" {
				cover = v["picture"]
			}
			if cover == "" {
				cover = v["profile_path"]
			}

			infobox := map[string]any{}
			excludeKeys := map[string]bool{
				"name": true, "title": true, "original_name": true, "avatar": true,
				"cover": true, "picture": true, "profile_path": true, "biography": true,
				"overview": true, "content": true, "summary": true, "aliases": true,
			}
			for k, val := range v {
				if !excludeKeys[k] && val != "" {
					infobox[k] = val
				}
			}

			var aliases []string
			if v["aliases"] != "" {
				for _, a := range strings.Split(v["aliases"], "\n") {
					a = strings.TrimSpace(a)
					if a != "" {
						aliases = append(aliases, a)
					}
				}
			}

			sub := WikiSubject{
				Name:         name,
				OriginalName: v["original_name"],
				Type:         entityType,
				SubType:      subType,
				Summary:      summary,
				CoverImage:   cover,
				Infobox:      infobox,
				Aliases:      aliases,
			}
			if _, err := s.RectifyCollectionRecordToWiki(ctx, item.srcID, item.target, item.key, sub); err == nil {
				rectifiedCount++
			}
		}
	}
	return rectifiedCount, nil
}
