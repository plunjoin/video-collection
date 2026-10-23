package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// WikiSubject 抽象词条实体模型（涵盖作品、人物、虚拟角色、时间线、组织等）
type WikiSubject struct {
	ID           int            `json:"id"`
	Name         string         `json:"name"`
	OriginalName string         `json:"original_name"`
	Type         string         `json:"type"`     // work(作品), person(人物), character(角色), event(事件/纪元), org(组织)
	SubType      string         `json:"sub_type"` // anime, movie, tokusatsu, game, actor, suit_actor, martial_arts, cv, director, timeline, era, etc.
	Summary      string         `json:"summary"`
	CoverImage   string         `json:"cover_image"`
	Infobox      map[string]any `json:"infobox"` // 动态属性卡 (JSONB)
	Aliases      []string       `json:"aliases"` // 别名列表
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
}

// WikiRelation 词条间的多向拓扑关系模型
type WikiRelation struct {
	ID              int          `json:"id"`
	SourceID        int          `json:"source_id"`
	TargetID        int          `json:"target_id"`
	RelationType    string       `json:"relation_type"`    // actor, suit_actor, martial_arts, cv, director, character_play, belongs_to_era, sequel, etc.
	RoleDescription string       `json:"role_description"` // 角色名或职能说明（如 "饰演: 安欣", "空我皮套演职", "动作监督"）
	SortOrder       int          `json:"sort_order"`
	CreatedAt       time.Time    `json:"created_at"`
	SourceSubject   *WikiSubject `json:"source_subject,omitempty"`
	TargetSubject   *WikiSubject `json:"target_subject,omitempty"`
}

// WikiCastMember is a live projection of editable Wiki subjects and relations.
type WikiCastMember struct {
	SubjectID       int    `json:"subject_id"`
	Name            string `json:"name"`
	OriginalName    string `json:"original_name,omitempty"`
	Type            string `json:"type"`
	SubType         string `json:"sub_type"`
	CoverImage      string `json:"cover_image"`
	Summary         string `json:"summary"`
	RelationType    string `json:"relation_type"`
	RoleDescription string `json:"role_description"`
	SortOrder       int    `json:"sort_order"`
}

// WikiSubjectDetail 词条完整详情聚合视图
type WikiSubjectDetail struct {
	WikiSubject
	ForwardRelations []WikiRelation `json:"forward_relations"` // 以该词条为起点的关系（如作品 -> 演职员）
	ReverseRelations []WikiRelation `json:"reverse_relations"` // 以该词条为终点的关系（如演职员 -> 参演作品）
	LinkedVideos     []VideoRecord  `json:"linked_videos"`     // 关联的线上流媒体播放视频条目
}

// WikiSubjectQuery 词条分页检索条件
type WikiSubjectQuery struct {
	Page     int
	PageSize int
	Type     string
	SubType  string
	Keyword  string
}

// WikiGraphNode 图谱节点
type WikiGraphNode struct {
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Type     string `json:"type"`
	SubType  string `json:"sub_type"`
	Cover    string `json:"cover"`
}

// WikiGraphEdge 图谱边
type WikiGraphEdge struct {
	Source   int    `json:"source"`
	Target   int    `json:"target"`
	Relation string `json:"relation"`
	Role     string `json:"role"`
}

// WikiGraphData 知识图谱前后端通用数据结构 (适配 ECharts / D3 / Cytoscape)
type WikiGraphData struct {
	Nodes []WikiGraphNode `json:"nodes"`
	Edges []WikiGraphEdge `json:"edges"`
}

// WikiStore 知识库与图谱管理接口
type WikiStore interface {
	CreateWikiSubject(ctx context.Context, s *WikiSubject) (int, error)
	UpdateWikiSubject(ctx context.Context, s *WikiSubject) error
	GetWikiSubjectByID(ctx context.Context, id int) (*WikiSubjectDetail, error)
	GetWikiSubjectByName(ctx context.Context, name string) (*WikiSubject, error)
	DeleteWikiSubject(ctx context.Context, id int) error
	ListWikiSubjects(ctx context.Context, q WikiSubjectQuery) ([]WikiSubject, int, error)

	CreateWikiRelation(ctx context.Context, r *WikiRelation) (int, error)
	DeleteWikiRelation(ctx context.Context, id int) error
	GetWikiRelationByID(ctx context.Context, id int) (*WikiRelation, error)
	ListWikiRelations(ctx context.Context, subjectID int) ([]WikiRelation, error)
	GetWikiGraph(ctx context.Context, rootID int, depth int) (*WikiGraphData, error)

	LinkVideoToSubject(ctx context.Context, videoID int, subjectID int) error
	SyncVideoToWikiSubject(ctx context.Context, videoID int) (*WikiSubject, error)
	ListWikiCastForSubject(ctx context.Context, subjectID int) ([]WikiCastMember, error)
	ListWikiCastForVideo(ctx context.Context, videoID int) ([]WikiCastMember, error)
}

func migrateWiki(tx *sql.Tx, id, timestamp string) error {
	schema := fmt.Sprintf(`
	CREATE TABLE IF NOT EXISTS wiki_subjects (
		id %s,
		name TEXT NOT NULL,
		original_name TEXT NOT NULL DEFAULT '',
		type TEXT NOT NULL,
		sub_type TEXT NOT NULL DEFAULT '',
		summary TEXT NOT NULL DEFAULT '',
		cover_image TEXT NOT NULL DEFAULT '',
		infobox TEXT NOT NULL DEFAULT '{}',
		aliases TEXT NOT NULL DEFAULT '[]',
		created_at %s NOT NULL,
		updated_at %s NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_wiki_subjects_type ON wiki_subjects(type, sub_type);
	CREATE INDEX IF NOT EXISTS idx_wiki_subjects_name ON wiki_subjects(name);

	CREATE TABLE IF NOT EXISTS wiki_relations (
		id %s,
		source_id INTEGER NOT NULL REFERENCES wiki_subjects(id) ON DELETE CASCADE,
		target_id INTEGER NOT NULL REFERENCES wiki_subjects(id) ON DELETE CASCADE,
		relation_type TEXT NOT NULL,
		role_description TEXT NOT NULL DEFAULT '',
		sort_order INTEGER NOT NULL DEFAULT 0,
		created_at %s NOT NULL,
		UNIQUE(source_id, target_id, relation_type, role_description)
	);
	CREATE INDEX IF NOT EXISTS idx_wiki_relations_src ON wiki_relations(source_id);
	CREATE INDEX IF NOT EXISTS idx_wiki_relations_tgt ON wiki_relations(target_id);
	CREATE INDEX IF NOT EXISTS idx_wiki_relations_type ON wiki_relations(relation_type);
	`, id, timestamp, timestamp, id, timestamp)
	if err := execScript(tx, schema); err != nil {
		return err
	}

	_, err := tx.Exec("INSERT INTO content_migrations(name) VALUES('wiki_knowledge_base_v1') ON CONFLICT(name) DO NOTHING")
	return err
}

func (s *SQLContentStore) CreateWikiSubject(ctx context.Context, sub *WikiSubject) (int, error) {
	if strings.TrimSpace(sub.Name) == "" {
		return 0, fmt.Errorf("词条名称不能为空")
	}
	if strings.TrimSpace(sub.Type) == "" {
		sub.Type = "work"
	}
	now := time.Now().UTC()
	sub.CreatedAt = now
	sub.UpdatedAt = now

	infoboxBytes, _ := json.Marshal(sub.Infobox)
	if len(sub.Infobox) == 0 {
		infoboxBytes = []byte("{}")
	}
	aliasesBytes, _ := json.Marshal(sub.Aliases)
	if len(sub.Aliases) == 0 {
		aliasesBytes = []byte("[]")
	}

	query := `INSERT INTO wiki_subjects(name, original_name, type, sub_type, summary, cover_image, infobox, aliases, created_at, updated_at)
	          VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING id`

	err := s.db.QueryRowContext(ctx, query,
		sub.Name, sub.OriginalName, sub.Type, sub.SubType,
		sub.Summary, sub.CoverImage, string(infoboxBytes), string(aliasesBytes),
		now.Format(time.RFC3339Nano), now.Format(time.RFC3339Nano),
	).Scan(&sub.ID)

	return sub.ID, err
}

func (s *SQLContentStore) UpdateWikiSubject(ctx context.Context, sub *WikiSubject) error {
	if sub.ID <= 0 {
		return fmt.Errorf("无效的词条ID")
	}
	if strings.TrimSpace(sub.Name) == "" {
		return fmt.Errorf("词条名称不能为空")
	}
	now := time.Now().UTC()
	sub.UpdatedAt = now

	infoboxBytes, _ := json.Marshal(sub.Infobox)
	if len(sub.Infobox) == 0 {
		infoboxBytes = []byte("{}")
	}
	aliasesBytes, _ := json.Marshal(sub.Aliases)
	if len(sub.Aliases) == 0 {
		aliasesBytes = []byte("[]")
	}

	query := `UPDATE wiki_subjects
	          SET name = $1, original_name = $2, type = $3, sub_type = $4,
	              summary = $5, cover_image = $6, infobox = $7, aliases = $8, updated_at = $9
	          WHERE id = $10`

	res, err := s.db.ExecContext(ctx, query,
		sub.Name, sub.OriginalName, sub.Type, sub.SubType,
		sub.Summary, sub.CoverImage, string(infoboxBytes), string(aliasesBytes),
		now.Format(time.RFC3339Nano), sub.ID,
	)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return errors.New("未找到对应词条记录")
	}
	return nil
}

func (s *SQLContentStore) DeleteWikiSubject(ctx context.Context, id int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM wiki_subjects WHERE id = $1", id)
	return err
}

func (s *SQLContentStore) GetWikiSubjectByName(ctx context.Context, name string) (*WikiSubject, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, errors.New("词条名称不能为空")
	}
	query := `SELECT id, name, original_name, type, sub_type, summary, cover_image, infobox, aliases, created_at, updated_at
	          FROM wiki_subjects WHERE name = $1 LIMIT 1`

	var sub WikiSubject
	var infoboxRaw, aliasesRaw, createdStr, updatedStr string
	err := s.db.QueryRowContext(ctx, query, name).Scan(
		&sub.ID, &sub.Name, &sub.OriginalName, &sub.Type, &sub.SubType,
		&sub.Summary, &sub.CoverImage, &infoboxRaw, &aliasesRaw,
		&createdStr, &updatedStr,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	_ = json.Unmarshal([]byte(infoboxRaw), &sub.Infobox)
	_ = json.Unmarshal([]byte(aliasesRaw), &sub.Aliases)
	sub.CreatedAt, _ = time.Parse(time.RFC3339Nano, createdStr)
	sub.UpdatedAt, _ = time.Parse(time.RFC3339Nano, updatedStr)
	return &sub, nil
}

func (s *SQLContentStore) GetWikiSubjectByID(ctx context.Context, id int) (*WikiSubjectDetail, error) {
	query := `SELECT id, name, original_name, type, sub_type, summary, cover_image, infobox, aliases, created_at, updated_at
	          FROM wiki_subjects WHERE id = $1`

	var d WikiSubjectDetail
	var infoboxRaw, aliasesRaw, createdStr, updatedStr string
	err := s.db.QueryRowContext(ctx, query, id).Scan(
		&d.ID, &d.Name, &d.OriginalName, &d.Type, &d.SubType,
		&d.Summary, &d.CoverImage, &infoboxRaw, &aliasesRaw,
		&createdStr, &updatedStr,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, errors.New("词条不存在")
	}
	if err != nil {
		return nil, err
	}
	_ = json.Unmarshal([]byte(infoboxRaw), &d.Infobox)
	_ = json.Unmarshal([]byte(aliasesRaw), &d.Aliases)
	d.CreatedAt, _ = time.Parse(time.RFC3339Nano, createdStr)
	d.UpdatedAt, _ = time.Parse(time.RFC3339Nano, updatedStr)

	relations, err := s.ListWikiRelations(ctx, id)
	if err != nil {
		return nil, err
	}
	d.ForwardRelations = []WikiRelation{}
	d.ReverseRelations = []WikiRelation{}
	d.LinkedVideos = []VideoRecord{}
	for _, rel := range relations {
		if rel.SourceID == id {
			d.ForwardRelations = append(d.ForwardRelations, rel)
		}
		if rel.TargetID == id {
			d.ReverseRelations = append(d.ReverseRelations, rel)
		}
	}

	// 3. 查询绑定的线上播放视频
	vRows, err := s.db.QueryContext(ctx, `
		SELECT id, COALESCE(subject_id, 0), name, sub_name, type_name, picture, year, remarks
		FROM videos
		WHERE subject_id = $1
		ORDER BY id ASC
		LIMIT 10`, id)
	if err == nil {
		defer vRows.Close()
		for vRows.Next() {
			var v VideoRecord
			if err := vRows.Scan(&v.ID, &v.SubjectID, &v.Name, &v.SubName, &v.TypeName, &v.Picture, &v.Year, &v.Remarks); err == nil {
				v.FillCompatFields()
				d.LinkedVideos = append(d.LinkedVideos, v)
			}
		}
	}

	return &d, nil
}

func (s *SQLContentStore) ListWikiSubjects(ctx context.Context, q WikiSubjectQuery) ([]WikiSubject, int, error) {
	page := q.Page
	if page < 1 {
		page = 1
	}
	pageSize := q.PageSize
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	offset := (page - 1) * pageSize

	var conditions []string
	var args []any
	argIdx := 1

	if strings.TrimSpace(q.Type) != "" {
		conditions = append(conditions, fmt.Sprintf("type = $%d", argIdx))
		args = append(args, strings.TrimSpace(q.Type))
		argIdx++
	}
	if strings.TrimSpace(q.SubType) != "" {
		conditions = append(conditions, fmt.Sprintf("sub_type = $%d", argIdx))
		args = append(args, strings.TrimSpace(q.SubType))
		argIdx++
	}
	if strings.TrimSpace(q.Keyword) != "" {
		kw := "%" + strings.TrimSpace(q.Keyword) + "%"
		conditions = append(conditions, fmt.Sprintf("(name LIKE $%d OR original_name LIKE $%d OR summary LIKE $%d)", argIdx, argIdx, argIdx))
		args = append(args, kw)
		argIdx++
	}

	whereClause := ""
	if len(conditions) > 0 {
		whereClause = "WHERE " + strings.Join(conditions, " AND ")
	}

	var total int
	countQuery := "SELECT COUNT(*) FROM wiki_subjects " + whereClause
	if err := s.db.QueryRowContext(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	listQuery := fmt.Sprintf(`SELECT id, name, original_name, type, sub_type, summary, cover_image, infobox, aliases, created_at, updated_at
	                          FROM wiki_subjects %s
	                          ORDER BY id DESC LIMIT $%d OFFSET $%d`, whereClause, argIdx, argIdx+1)
	args = append(args, pageSize, offset)

	rows, err := s.db.QueryContext(ctx, listQuery, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var list []WikiSubject
	for rows.Next() {
		var sub WikiSubject
		var infoboxRaw, aliasesRaw, createdStr, updatedStr string
		if err := rows.Scan(
			&sub.ID, &sub.Name, &sub.OriginalName, &sub.Type, &sub.SubType,
			&sub.Summary, &sub.CoverImage, &infoboxRaw, &aliasesRaw,
			&createdStr, &updatedStr,
		); err == nil {
			_ = json.Unmarshal([]byte(infoboxRaw), &sub.Infobox)
			_ = json.Unmarshal([]byte(aliasesRaw), &sub.Aliases)
			sub.CreatedAt, _ = time.Parse(time.RFC3339Nano, createdStr)
			sub.UpdatedAt, _ = time.Parse(time.RFC3339Nano, updatedStr)
			list = append(list, sub)
		}
	}

	return list, total, nil
}

func (s *SQLContentStore) CreateWikiRelation(ctx context.Context, r *WikiRelation) (int, error) {
	if r.SourceID <= 0 || r.TargetID <= 0 {
		return 0, fmt.Errorf("关联的两端词条ID必须有效")
	}
	if r.SourceID == r.TargetID {
		return 0, fmt.Errorf("不能与词条自身建立关联")
	}
	if strings.TrimSpace(r.RelationType) == "" {
		return 0, fmt.Errorf("关联关系类型不能为空")
	}
	now := time.Now().UTC()
	r.CreatedAt = now

	query := `INSERT INTO wiki_relations(source_id, target_id, relation_type, role_description, sort_order, created_at)
	          VALUES($1, $2, $3, $4, $5, $6)
	          ON CONFLICT(source_id, target_id, relation_type, role_description) DO UPDATE SET sort_order = excluded.sort_order
	          RETURNING id`

	err := s.db.QueryRowContext(ctx, query,
		r.SourceID, r.TargetID, r.RelationType, r.RoleDescription, r.SortOrder, now.Format(time.RFC3339Nano),
	).Scan(&r.ID)

	return r.ID, err
}

func (s *SQLContentStore) DeleteWikiRelation(ctx context.Context, id int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM wiki_relations WHERE id = $1", id)
	return err
}

func (s *SQLContentStore) GetWikiRelationByID(ctx context.Context, id int) (*WikiRelation, error) {
	if id <= 0 {
		return nil, errors.New("无效的关系 ID")
	}
	var rel WikiRelation
	var relCreated string
	err := s.db.QueryRowContext(ctx, `SELECT id, source_id, target_id, relation_type, role_description, sort_order, created_at
		FROM wiki_relations WHERE id=$1`, id).Scan(
		&rel.ID, &rel.SourceID, &rel.TargetID, &rel.RelationType, &rel.RoleDescription, &rel.SortOrder, &relCreated,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	rel.CreatedAt, _ = time.Parse(time.RFC3339Nano, relCreated)
	return &rel, nil
}

func (s *SQLContentStore) ListWikiRelations(ctx context.Context, subjectID int) ([]WikiRelation, error) {
	query := `
		SELECT r.id, r.source_id, r.target_id, r.relation_type, r.role_description, r.sort_order, r.created_at,
		       s.name, s.type, s.sub_type, s.cover_image, s.summary, s.original_name,
		       t.name, t.type, t.sub_type, t.cover_image, t.summary, t.original_name
		FROM wiki_relations r
		JOIN wiki_subjects s ON s.id = r.source_id
		JOIN wiki_subjects t ON t.id = r.target_id
		WHERE r.source_id = $1 OR r.target_id = $1
		ORDER BY r.sort_order ASC, r.id ASC`

	rows, err := s.db.QueryContext(ctx, query, subjectID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var rels []WikiRelation
	for rows.Next() {
		var rel WikiRelation
		var sSub, tSub WikiSubject
		var relCreated string
		if err := rows.Scan(
			&rel.ID, &rel.SourceID, &rel.TargetID, &rel.RelationType, &rel.RoleDescription, &rel.SortOrder, &relCreated,
			&sSub.Name, &sSub.Type, &sSub.SubType, &sSub.CoverImage, &sSub.Summary, &sSub.OriginalName,
			&tSub.Name, &tSub.Type, &tSub.SubType, &tSub.CoverImage, &tSub.Summary, &tSub.OriginalName,
		); err != nil {
			return nil, err
		} else {
			sSub.ID = rel.SourceID
			tSub.ID = rel.TargetID
			rel.SourceSubject = &sSub
			rel.TargetSubject = &tSub
			rel.CreatedAt, _ = time.Parse(time.RFC3339Nano, relCreated)
			rels = append(rels, rel)
		}
	}
	return rels, rows.Err()
}

// GetWikiGraph 获取以 rootID 为中心的图谱拓扑数据 (支持 1 到 2 层深度)
func (s *SQLContentStore) GetWikiGraph(ctx context.Context, rootID int, depth int) (*WikiGraphData, error) {
	if depth < 1 {
		depth = 1
	}
	if depth > 2 {
		depth = 2
	}

	nodesMap := make(map[int]WikiGraphNode)
	var edges []WikiGraphEdge
	visitedEdge := make(map[string]bool)

	currentFrontier := []int{rootID}
	allSubjectIDs := map[int]bool{rootID: true}

	for d := 0; d < depth; d++ {
		if len(currentFrontier) == 0 {
			break
		}
		var nextFrontier []int

		for _, currentID := range currentFrontier {
			rels, err := s.ListWikiRelations(ctx, currentID)
			if err != nil {
				continue
			}
			for _, r := range rels {
				edgeKey := fmt.Sprintf("%d-%d-%s", r.SourceID, r.TargetID, r.RelationType)
				if !visitedEdge[edgeKey] {
					visitedEdge[edgeKey] = true
					edges = append(edges, WikiGraphEdge{
						Source:   r.SourceID,
						Target:   r.TargetID,
						Relation: r.RelationType,
						Role:     r.RoleDescription,
					})
				}
				neighbor := r.TargetID
				if neighbor == currentID {
					neighbor = r.SourceID
				}
				if !allSubjectIDs[neighbor] {
					allSubjectIDs[neighbor] = true
					nextFrontier = append(nextFrontier, neighbor)
				}
			}
		}
		currentFrontier = nextFrontier
	}

	// 批量查询所有节点的基本信息
	if len(allSubjectIDs) > 0 {
		var ids []string
		for id := range allSubjectIDs {
			ids = append(ids, fmt.Sprintf("%d", id))
		}
		idListStr := strings.Join(ids, ",")
		query := fmt.Sprintf("SELECT id, name, type, sub_type, cover_image FROM wiki_subjects WHERE id IN (%s)", idListStr)
		rows, err := s.db.QueryContext(ctx, query)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var node WikiGraphNode
				if err := rows.Scan(&node.ID, &node.Name, &node.Type, &node.SubType, &node.Cover); err == nil {
					nodesMap[node.ID] = node
				}
			}
		}
	}

	nodes := make([]WikiGraphNode, 0, len(nodesMap))
	for _, n := range nodesMap {
		nodes = append(nodes, n)
	}

	return &WikiGraphData{
		Nodes: nodes,
		Edges: edges,
	}, nil
}

func (s *SQLContentStore) LinkVideoToSubject(ctx context.Context, videoID int, subjectID int) error {
	_, err := s.db.ExecContext(ctx, "UPDATE videos SET subject_id = $1 WHERE id = $2", subjectID, videoID)
	return err
}

// collectionPersonMeta is cover/summary mined from collection_records for a person name.
type collectionPersonMeta struct {
	Cover        string
	Summary      string
	OriginalName string
}

func firstNonEmptyString(vals ...string) string {
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

func wikiNameMatches(candidate, want string) bool {
	candidate = strings.TrimSpace(candidate)
	want = strings.TrimSpace(want)
	if candidate == "" || want == "" {
		return false
	}
	if strings.EqualFold(candidate, want) {
		return true
	}
	// Allow "成龙 (Jackie Chan)" style payloads to match "成龙".
	if i := strings.IndexAny(candidate, "（("); i > 0 {
		return strings.EqualFold(strings.TrimSpace(candidate[:i]), want)
	}
	return false
}

// lookupCollectionPersonMeta finds avatar/cover/summary for a person name in collection_records.
// Prefers records that look like people (have avatar/biography, no play_url).
func (s *SQLContentStore) lookupCollectionPersonMeta(ctx context.Context, name string) collectionPersonMeta {
	var out collectionPersonMeta
	name = strings.TrimSpace(name)
	if name == "" {
		return out
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT payload FROM collection_records
		WHERE payload LIKE $1
		ORDER BY updated_at DESC
		LIMIT 80`, "%"+name+"%")
	if err != nil {
		return out
	}
	defer rows.Close()

	type scored struct {
		meta  collectionPersonMeta
		score int
	}
	best := scored{}
	for rows.Next() {
		var payloadStr string
		if err := rows.Scan(&payloadStr); err != nil {
			continue
		}
		var v map[string]string
		if err := json.Unmarshal([]byte(payloadStr), &v); err != nil || v == nil {
			continue
		}
		recordName := firstNonEmptyString(v["name"], v["title"])
		matched := wikiNameMatches(recordName, name) || wikiNameMatches(v["original_name"], name)
		if !matched && v["aliases"] != "" {
			for _, a := range strings.Split(v["aliases"], "\n") {
				if wikiNameMatches(a, name) {
					matched = true
					break
				}
			}
		}
		if !matched {
			continue
		}
		// Skip video-shaped payloads; person covers live on person/record targets.
		if strings.TrimSpace(v["play_url"]) != "" || strings.TrimSpace(v["vod_play_url"]) != "" {
			continue
		}
		meta := collectionPersonMeta{
			Cover:        firstNonEmptyString(v["avatar"], v["cover"], v["picture"], v["profile_path"], v["vod_pic"]),
			Summary:      firstNonEmptyString(v["biography"], v["overview"], v["summary"], v["content"]),
			OriginalName: strings.TrimSpace(v["original_name"]),
		}
		score := 0
		if meta.Cover != "" {
			score += 2
		}
		if meta.Summary != "" {
			score++
		}
		if v["avatar"] != "" || v["biography"] != "" || v["role_type"] != "" {
			score += 2
		}
		if score > best.score {
			best = scored{meta: meta, score: score}
		}
		if best.score >= 4 && best.meta.Cover != "" {
			break
		}
	}
	return best.meta
}

// fillWikiSubjectGaps writes only empty fields from incoming values; never overwrites editors.
func (s *SQLContentStore) fillWikiSubjectGaps(ctx context.Context, sub *WikiSubject, cover, summary, originalName string) error {
	if sub == nil || sub.ID <= 0 {
		return nil
	}
	changed := false
	if strings.TrimSpace(sub.CoverImage) == "" && strings.TrimSpace(cover) != "" {
		sub.CoverImage = strings.TrimSpace(cover)
		changed = true
	}
	if strings.TrimSpace(sub.Summary) == "" && strings.TrimSpace(summary) != "" {
		sub.Summary = strings.TrimSpace(summary)
		changed = true
	}
	if strings.TrimSpace(sub.OriginalName) == "" && strings.TrimSpace(originalName) != "" {
		sub.OriginalName = strings.TrimSpace(originalName)
		changed = true
	}
	if !changed {
		return nil
	}
	return s.UpdateWikiSubject(ctx, sub)
}

// SyncVideoToWikiSubject 智能桥接：从已有视频冷启动生成对应 Wiki 作品条目与演职员关系网。
// 作品封面/简介来自 videos；人物空封面优先回填 collection_records 里同名影人的 avatar/cover。
// 已有非空 Wiki 字段（含管理员编辑）不会被覆盖。
func (s *SQLContentStore) SyncVideoToWikiSubject(ctx context.Context, videoID int) (*WikiSubject, error) {
	var v VideoRecord
	query := `SELECT id, COALESCE(subject_id, 0), name, sub_name, type_id, type_name, picture, actor, director, area, language, year, remarks, content
	          FROM videos WHERE id = $1`
	err := s.db.QueryRowContext(ctx, query, videoID).Scan(
		&v.ID, &v.SubjectID, &v.Name, &v.SubName, &v.TypeID, &v.TypeName, &v.Picture,
		&v.Actor, &v.Director, &v.Area, &v.Language, &v.Year, &v.Remarks, &v.Content,
	)
	if err != nil {
		return nil, fmt.Errorf("视频未找到: %w", err)
	}

	// 1. 检查或创建作品词条
	var subject *WikiSubject
	if v.SubjectID > 0 {
		detail, loadErr := s.GetWikiSubjectByID(ctx, v.SubjectID)
		if loadErr != nil {
			return nil, loadErr
		}
		subject = &detail.WikiSubject
	} else {
		subject, err = s.GetWikiSubjectByName(ctx, v.Name)
	}
	if err != nil {
		return nil, err
	}
	if subject == nil {
		subType := "movie"
		typeName := strings.ToLower(v.TypeName)
		if strings.Contains(typeName, "剧") {
			subType = "tv"
		} else if strings.Contains(typeName, "漫") {
			subType = "anime"
		} else if strings.Contains(typeName, "特摄") {
			subType = "tokusatsu"
		}

		newSubject := &WikiSubject{
			Name:         v.Name,
			OriginalName: v.SubName,
			Type:         "work",
			SubType:      subType,
			Summary:      v.Content,
			CoverImage:   v.Picture,
			Infobox: map[string]any{
				"year":     v.Year,
				"area":     v.Area,
				"language": v.Language,
				"remarks":  v.Remarks,
			},
		}
		id, err := s.CreateWikiSubject(ctx, newSubject)
		if err != nil {
			return nil, err
		}
		newSubject.ID = id
		subject = newSubject
	}

	// Only fill gaps: Wiki editors own all non-empty metadata.
	changed := false
	if subject.Type == "work" {
		if strings.TrimSpace(subject.Summary) == "" && strings.TrimSpace(v.Content) != "" {
			subject.Summary = v.Content
			changed = true
		}
		if strings.TrimSpace(subject.CoverImage) == "" && strings.TrimSpace(v.Picture) != "" {
			subject.CoverImage = v.Picture
			changed = true
		}
		if subject.Infobox == nil {
			subject.Infobox = map[string]any{}
		}
		for key, value := range map[string]string{"year": v.Year, "area": v.Area, "language": v.Language, "remarks": v.Remarks} {
			existing := subject.Infobox[key]
			if (existing == nil || strings.TrimSpace(fmt.Sprint(existing)) == "") && strings.TrimSpace(value) != "" {
				subject.Infobox[key] = value
				changed = true
			}
		}
	}
	if changed {
		if err := s.UpdateWikiSubject(ctx, subject); err != nil {
			return nil, err
		}
	}
	if err := s.LinkVideoToSubject(ctx, v.ID, subject.ID); err != nil {
		return nil, err
	}

	// 2. 提取演员并建立关系；空人物字段回填采集库同名影人封面/简介
	splitTokens := func(s string) []string {
		f := func(c rune) bool {
			return c == ',' || c == '/' || c == '、' || c == '|' || c == ';' || c == '，'
		}
		parts := strings.FieldsFunc(s, f)
		var res []string
		for _, p := range parts {
			trimmed := strings.TrimSpace(p)
			if trimmed != "" {
				res = append(res, trimmed)
			}
		}
		return res
	}

	for _, credit := range []struct{ names, relationType, role string }{
		{v.Actor, "actor", "主演"}, {v.Director, "director", "导演"},
	} {
		for idx, name := range splitTokens(credit.names) {
			person, err := s.GetWikiSubjectByName(ctx, name)
			if err != nil {
				return nil, err
			}
			meta := s.lookupCollectionPersonMeta(ctx, name)
			if person == nil {
				person = &WikiSubject{
					Name:         name,
					Type:         "person",
					SubType:      credit.relationType,
					CoverImage:   meta.Cover,
					Summary:      meta.Summary,
					OriginalName: meta.OriginalName,
				}
				if _, err := s.CreateWikiSubject(ctx, person); err != nil {
					return nil, err
				}
			} else if err := s.fillWikiSubjectGaps(ctx, person, meta.Cover, meta.Summary, meta.OriginalName); err != nil {
				return nil, err
			}
			if _, err := s.CreateWikiRelation(ctx, &WikiRelation{
				SourceID: subject.ID, TargetID: person.ID, RelationType: credit.relationType,
				RoleDescription: credit.role, SortOrder: idx + 1,
			}); err != nil {
				return nil, err
			}
		}
	}

	return subject, nil
}

// ListWikiCastForSubject reads current Wiki metadata; no separate cast store is maintained.
func (s *SQLContentStore) ListWikiCastForSubject(ctx context.Context, subjectID int) ([]WikiCastMember, error) {
	cast := []WikiCastMember{}
	rows, err := s.db.QueryContext(ctx, `
 SELECT t.id, t.name, t.original_name, t.type, t.sub_type, t.cover_image, t.summary,
        r.relation_type, r.role_description, r.sort_order
 FROM wiki_relations r JOIN wiki_subjects t ON t.id = r.target_id
 WHERE r.source_id = $1 AND (r.relation_type IN ('actor','director','suit_actor','cv','martial_arts') OR t.type = 'person')
 ORDER BY CASE WHEN r.relation_type IN ('actor','suit_actor','cv') THEN 0 ELSE 1 END,
          r.sort_order ASC, r.id ASC`, subjectID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var member WikiCastMember
		if err := rows.Scan(&member.SubjectID, &member.Name, &member.OriginalName, &member.Type, &member.SubType, &member.CoverImage, &member.Summary, &member.RelationType, &member.RoleDescription, &member.SortOrder); err != nil {
			return nil, err
		}
		cast = append(cast, member)
	}
	return cast, rows.Err()
}

func (s *SQLContentStore) ListWikiCastForVideo(ctx context.Context, videoID int) ([]WikiCastMember, error) {
	var subjectID int
	if err := s.db.QueryRowContext(ctx, "SELECT COALESCE(subject_id, 0) FROM videos WHERE id = $1", videoID).Scan(&subjectID); err != nil {
		return nil, err
	}
	return s.ListWikiCastForSubject(ctx, subjectID)
}
