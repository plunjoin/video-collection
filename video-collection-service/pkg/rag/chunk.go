package rag

import (
	"encoding/json"
	"fmt"
	"strings"

	"video-collection-service/pkg/store"
)

const (
	defaultChunkSize    = 900
	defaultChunkOverlap = 120
)

// BuildWikiSubjectChunks 将词条摘要、属性卡与别名拆成可检索块。
func BuildWikiSubjectChunks(d *store.WikiSubjectDetail) []DocumentChunk {
	if d == nil {
		return nil
	}
	var chunks []DocumentChunk
	metaBase := map[string]any{
		"subject_name": d.Name,
		"subject_type": d.Type,
		"sub_type":     d.SubType,
	}
	if d.OriginalName != "" {
		metaBase["original_name"] = d.OriginalName
	}

	header := fmt.Sprintf("词条：%s", d.Name)
	if d.OriginalName != "" {
		header += fmt.Sprintf("（%s）", d.OriginalName)
	}
	header += fmt.Sprintf(" [%s/%s]", d.Type, d.SubType)

	if strings.TrimSpace(d.Summary) != "" {
		body := header + "\n" + strings.TrimSpace(d.Summary)
		for i, part := range splitText(body, defaultChunkSize, defaultChunkOverlap) {
			meta := copyMeta(metaBase)
			meta["section"] = "summary"
			chunks = append(chunks, DocumentChunk{
				SourceType: SourceWikiSubject,
				SourceID:   fmt.Sprintf("%d", d.ID),
				SubjectID:  d.ID,
				ChunkIndex: i,
				Text:       part,
				Metadata:   meta,
			})
		}
	}

	if len(d.Infobox) > 0 {
		var lines []string
		for k, v := range d.Infobox {
			lines = append(lines, fmt.Sprintf("%s: %v", k, v))
		}
		infoboxText := header + "\n属性卡：\n" + strings.Join(lines, "\n")
		idx := len(chunks)
		for _, part := range splitText(infoboxText, defaultChunkSize, defaultChunkOverlap) {
			meta := copyMeta(metaBase)
			meta["section"] = "infobox"
			chunks = append(chunks, DocumentChunk{
				SourceType: SourceWikiSubject,
				SourceID:   fmt.Sprintf("%d", d.ID),
				SubjectID:  d.ID,
				ChunkIndex: idx,
				Text:       part,
				Metadata:   meta,
			})
			idx++
		}
	}

	if len(d.Aliases) > 0 {
		aliasText := header + "\n别名：" + strings.Join(d.Aliases, "、")
		idx := len(chunks)
		for _, part := range splitText(aliasText, defaultChunkSize, defaultChunkOverlap) {
			meta := copyMeta(metaBase)
			meta["section"] = "aliases"
			chunks = append(chunks, DocumentChunk{
				SourceType: SourceWikiSubject,
				SourceID:   fmt.Sprintf("%d", d.ID),
				SubjectID:  d.ID,
				ChunkIndex: idx,
				Text:       part,
				Metadata:   meta,
			})
			idx++
		}
	}

	return chunks
}

// BuildWikiRelationChunks 为词条的关系上下文生成描述块（便于图关系问答）。
func BuildWikiRelationChunks(d *store.WikiSubjectDetail) []DocumentChunk {
	if d == nil {
		return nil
	}
	var chunks []DocumentChunk
	idx := 0
	appendRel := func(rel store.WikiRelation, direction string) {
		var peerName, peerType string
		if direction == "forward" && rel.TargetSubject != nil {
			peerName = rel.TargetSubject.Name
			peerType = rel.TargetSubject.Type + "/" + rel.TargetSubject.SubType
		}
		if direction == "reverse" && rel.SourceSubject != nil {
			peerName = rel.SourceSubject.Name
			peerType = rel.SourceSubject.Type + "/" + rel.SourceSubject.SubType
		}
		if peerName == "" {
			return
		}
		role := strings.TrimSpace(rel.RoleDescription)
		text := fmt.Sprintf("词条「%s」的关系（%s）：%s → %s", d.Name, rel.RelationType, d.Name, peerName)
		if role != "" {
			text += "（" + role + "）"
		}
		text += fmt.Sprintf("；关联实体类型 %s", peerType)
		meta := map[string]any{
			"subject_name":  d.Name,
			"relation_id":   rel.ID,
			"relation_type": rel.RelationType,
			"direction":     direction,
			"peer_name":     peerName,
		}
		chunks = append(chunks, DocumentChunk{
			SourceType: SourceWikiRelation,
			SourceID:   fmt.Sprintf("%d", rel.ID),
			SubjectID:  d.ID,
			ChunkIndex: idx,
			Text:       text,
			Metadata:   meta,
		})
		idx++
	}
	for _, rel := range d.ForwardRelations {
		appendRel(rel, "forward")
	}
	for _, rel := range d.ReverseRelations {
		appendRel(rel, "reverse")
	}
	return chunks
}

// BuildContentChunks 将资讯/社区正文拆块；关联了 Wiki 词条时块携带 subject_id，
// 检索命中即可回链到对应作品/人物详情。
func BuildContentChunks(c *store.Content) []DocumentChunk {
	if c == nil {
		return nil
	}
	sourceType := SourceNews
	if c.Kind == "post" {
		sourceType = SourcePost
	}
	metaBase := map[string]any{
		"title":    c.Title,
		"kind":     c.Kind,
		"category": c.Category,
		"status":   c.Status,
	}
	if c.SubjectID > 0 {
		metaBase["subject_id"] = c.SubjectID
	}
	header := fmt.Sprintf("[%s] %s", c.Kind, c.Title)
	var bodyParts []string
	if strings.TrimSpace(c.Summary) != "" {
		bodyParts = append(bodyParts, strings.TrimSpace(c.Summary))
	}
	if strings.TrimSpace(c.Content) != "" {
		bodyParts = append(bodyParts, strings.TrimSpace(c.Content))
	}
	if len(bodyParts) == 0 {
		return nil
	}
	full := header + "\n" + strings.Join(bodyParts, "\n\n")
	var chunks []DocumentChunk
	for i, part := range splitText(full, defaultChunkSize, defaultChunkOverlap) {
		chunks = append(chunks, DocumentChunk{
			SourceType: sourceType,
			SourceID:   fmt.Sprintf("%d", c.ID),
			SubjectID:  c.SubjectID,
			ChunkIndex: i,
			Text:       part,
			Metadata:   copyMeta(metaBase),
		})
	}
	return chunks
}

func splitText(text string, size, overlap int) []string {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}
	if size <= 0 {
		return []string{text}
	}
	if overlap >= size {
		overlap = size / 4
	}
	runes := []rune(text)
	if len(runes) <= size {
		return []string{text}
	}
	var parts []string
	start := 0
	for start < len(runes) {
		end := start + size
		if end > len(runes) {
			end = len(runes)
		}
		parts = append(parts, strings.TrimSpace(string(runes[start:end])))
		if end >= len(runes) {
			break
		}
		start = end - overlap
		if start < 0 {
			start = 0
		}
	}
	return parts
}

func copyMeta(in map[string]any) map[string]any {
	if len(in) == 0 {
		return map[string]any{}
	}
	out := make(map[string]any, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}

// MetadataJSON 序列化元数据供存储层使用。
func MetadataJSON(meta map[string]any) string {
	if len(meta) == 0 {
		return "{}"
	}
	b, err := json.Marshal(meta)
	if err != nil {
		return "{}"
	}
	return string(b)
}
