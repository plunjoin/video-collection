package rag

import (
	"context"
	"fmt"
	"strings"
)

// Ask retrieves evidence, optionally enriches it with one-hop Wiki graphs,
// and asks the configured chat model to answer with source references.
func (s *Service) Ask(ctx context.Context, query string, topK int, sourceType string) (*AskResponse, error) {
	search, err := s.Search(ctx, query, topK, sourceType)
	if err != nil {
		return nil, err
	}
	var prompt strings.Builder
	fmt.Fprintf(&prompt, "问题：%s\n\n上下文片段（引用编号与 citations 数组顺序一致）：\n", search.Query)
	for i, hit := range search.Results {
		fmt.Fprintf(&prompt, "\n[%d] 来源=%s，source_id=%s，subject_id=%d，chunk_index=%d\n%s\n", i+1, hit.SourceType, hit.SourceID, hit.SubjectID, hit.ChunkIndex, hit.Text)
	}
	if len(search.Results) == 0 {
		prompt.WriteString("（没有检索到资料，请明确说明现有资料不足以回答。）\n")
	}

	seen := map[int]bool{}
	var graphRoots []string
	if s.wiki != nil {
		for _, hit := range search.Results {
			if hit.SubjectID <= 0 || seen[hit.SubjectID] {
				continue
			}
			if len(seen) >= 3 {
				break
			}
			seen[hit.SubjectID] = true
			graph, err := s.wiki.GetWikiGraph(ctx, hit.SubjectID, 1)
			if err != nil {
				s.logf("ask graph %d: %v", hit.SubjectID, err)
				continue // Graph enrichment is optional; retrieved chunks still work.
			}
			if graph == nil || len(graph.Nodes) == 0 {
				continue
			}
			names := map[int]string{}
			for _, node := range graph.Nodes {
				// Keep graph snippets compact even for highly connected subjects.
				names[node.ID] = string([]rune(node.Name)[:min(len([]rune(node.Name)), 160)])
			}
			fmt.Fprintf(&prompt, "\n[图谱:%d] %s 的一层关系摘要：\n", hit.SubjectID, names[hit.SubjectID])
			for i, edge := range graph.Edges {
				if i >= 30 {
					prompt.WriteString("（其余关系省略）\n")
					break
				}
				fmt.Fprintf(&prompt, "%s（%d） --%s / %s--> %s（%d）\n", names[edge.Source], edge.Source, edge.Relation, edge.Role, names[edge.Target], edge.Target)
			}
			graphRoots = append(graphRoots, fmt.Sprintf("%d", hit.SubjectID))
		}
	}
	prompt.WriteString("\n请仅依据以上资料回答问题并标注引用；资料不足时明确说明。")
	answer, err := s.chat.Complete(ctx, prompt.String())
	if err != nil {
		return nil, err
	}
	result := &AskResponse{
		Query: search.Query, Answer: answer, Citations: search.Results,
		Model: s.chat.model, Embedder: s.EmbedderName(), TopK: search.TopK,
	}
	if len(graphRoots) > 0 {
		result.GraphNote = "已使用一层 Wiki 图谱，根词条 ID：" + strings.Join(graphRoots, "、") + "（每个最多 30 条关系）"
	}
	return result, nil
}
