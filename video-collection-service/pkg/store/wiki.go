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
	ListWikiRelations(ctx context.Context, subjectID int) ([]WikiRelation, error)
	GetWikiGraph(ctx context.Context, rootID int, depth int) (*WikiGraphData, error)

	LinkVideoToSubject(ctx context.Context, videoID int, subjectID int) error
	SyncVideoToWikiSubject(ctx context.Context, videoID int) (*WikiSubject, error)
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
	if _, err := tx.Exec(schema); err != nil {
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

	// 1. 查询以该词条为起点的正向关系（携带 TargetSubject 摘要）
	fRows, err := s.db.QueryContext(ctx, `
		SELECT r.id, r.source_id, r.target_id, r.relation_type, r.role_description, r.sort_order, r.created_at,
		       t.id, t.name, t.type, t.sub_type, t.cover_image
		FROM wiki_relations r
		JOIN wiki_subjects t ON t.id = r.target_id
		WHERE r.source_id = $1
		ORDER BY r.sort_order ASC, r.id ASC`, id)
	if err == nil {
		defer fRows.Close()
		for fRows.Next() {
			var rel WikiRelation
			var tgt WikiSubject
			var relCreated string
			if err := fRows.Scan(
				&rel.ID, &rel.SourceID, &rel.TargetID, &rel.RelationType, &rel.RoleDescription, &rel.SortOrder, &relCreated,
				&tgt.ID, &tgt.Name, &tgt.Type, &tgt.SubType, &tgt.CoverImage,
			); err == nil {
				rel.CreatedAt, _ = time.Parse(time.RFC3339Nano, relCreated)
				rel.TargetSubject = &tgt
				d.ForwardRelations = append(d.ForwardRelations, rel)
			}
		}
	}

	// 2. 查询以该词条为终点的反向关系（携带 SourceSubject 摘要，如演员反查其出演的作品）
	rRows, err := s.db.QueryContext(ctx, `
		SELECT r.id, r.source_id, r.target_id, r.relation_type, r.role_description, r.sort_order, r.created_at,
		       s.id, s.name, s.type, s.sub_type, s.cover_image
		FROM wiki_relations r
		JOIN wiki_subjects s ON s.id = r.source_id
		WHERE r.target_id = $1
		ORDER BY r.sort_order ASC, r.id ASC`, id)
	if err == nil {
		defer rRows.Close()
		for rRows.Next() {
			var rel WikiRelation
			var srcSub WikiSubject
			var relCreated string
			if err := rRows.Scan(
				&rel.ID, &rel.SourceID, &rel.TargetID, &rel.RelationType, &rel.RoleDescription, &rel.SortOrder, &relCreated,
				&srcSub.ID, &srcSub.Name, &srcSub.Type, &srcSub.SubType, &srcSub.CoverImage,
			); err == nil {
				rel.CreatedAt, _ = time.Parse(time.RFC3339Nano, relCreated)
				rel.SourceSubject = &srcSub
				d.ReverseRelations = append(d.ReverseRelations, rel)
			}
		}
	}

	// 3. 查询绑定的线上播放视频
	vRows, err := s.db.QueryContext(ctx, `
		SELECT id, name, sub_name, type_name, picture, year, remarks
		FROM videos
		WHERE subject_id = $1
		LIMIT 10`, id)
	if err == nil {
		defer vRows.Close()
		for vRows.Next() {
			var v VideoRecord
			if err := vRows.Scan(&v.ID, &v.Name, &v.SubName, &v.TypeName, &v.Picture, &v.Year, &v.Remarks); err == nil {
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

func (s *SQLContentStore) ListWikiRelations(ctx context.Context, subjectID int) ([]WikiRelation, error) {
	query := `
		SELECT r.id, r.source_id, r.target_id, r.relation_type, r.role_description, r.sort_order, r.created_at,
		       s.name, s.type, s.sub_type, s.cover_image,
		       t.name, t.type, t.sub_type, t.cover_image
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
			&sSub.Name, &sSub.Type, &sSub.SubType, &sSub.CoverImage,
			&tSub.Name, &tSub.Type, &tSub.SubType, &tSub.CoverImage,
		); err == nil {
			sSub.ID = rel.SourceID
			tSub.ID = rel.TargetID
			rel.SourceSubject = &sSub
			rel.TargetSubject = &tSub
			rel.CreatedAt, _ = time.Parse(time.RFC3339Nano, relCreated)
			rels = append(rels, rel)
		}
	}
	return rels, nil
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

// SyncVideoToWikiSubject 智能桥接：从已有视频冷启动生成对应 Wiki 作品条目与演职员关系网
func (s *SQLContentStore) SyncVideoToWikiSubject(ctx context.Context, videoID int) (*WikiSubject, error) {
	var v VideoRecord
	query := `SELECT id, name, sub_name, type_id, type_name, picture, actor, director, area, language, year, remarks, content
	          FROM videos WHERE id = $1`
	err := s.db.QueryRowContext(ctx, query, videoID).Scan(
		&v.ID, &v.Name, &v.SubName, &v.TypeID, &v.TypeName, &v.Picture,
		&v.Actor, &v.Director, &v.Area, &v.Language, &v.Year, &v.Remarks, &v.Content,
	)
	if err != nil {
		return nil, fmt.Errorf("视频未找到: %w", err)
	}

	// 1. 检查或创建作品词条
	subject, err := s.GetWikiSubjectByName(ctx, v.Name)
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

	// 绑定视频与词条
	_ = s.LinkVideoToSubject(ctx, v.ID, subject.ID)

	// 2. 提取演员并建立关系
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

	actors := splitTokens(v.Actor)
	for idx, actorName := range actors {
		person, _ := s.GetWikiSubjectByName(ctx, actorName)
		if person == nil {
			person = &WikiSubject{
				Name:    actorName,
				Type:    "person",
				SubType: "actor",
			}
			pID, err := s.CreateWikiSubject(ctx, person)
			if err == nil {
				person.ID = pID
			}
		}
		if person != nil && person.ID > 0 {
			_, _ = s.CreateWikiRelation(ctx, &WikiRelation{
				SourceID:        subject.ID,
				TargetID:        person.ID,
				RelationType:    "actor",
				RoleDescription: "主演",
				SortOrder:       idx + 1,
			})
		}
	}

	// 3. 提取导演并建立关系
	directors := splitTokens(v.Director)
	for idx, dirName := range directors {
		dirPerson, _ := s.GetWikiSubjectByName(ctx, dirName)
		if dirPerson == nil {
			dirPerson = &WikiSubject{
				Name:    dirName,
				Type:    "person",
				SubType: "director",
			}
			dID, err := s.CreateWikiSubject(ctx, dirPerson)
			if err == nil {
				dirPerson.ID = dID
			}
		}
		if dirPerson != nil && dirPerson.ID > 0 {
			_, _ = s.CreateWikiRelation(ctx, &WikiRelation{
				SourceID:        subject.ID,
				TargetID:        dirPerson.ID,
				RelationType:    "director",
				RoleDescription: "导演",
				SortOrder:       idx + 1,
			})
		}
	}

	return subject, nil
}
