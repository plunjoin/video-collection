package rag

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync"
	"unicode"

	"video-collection-service/pkg/store"
)

// Indexer 抽象 RAG 持久化，便于测试。
type Indexer interface {
	ReplaceRAGChunks(ctx context.Context, sourceType, sourceID string, rows []store.RAGChunkRow) error
	DeleteRAGChunksBySource(ctx context.Context, sourceType, sourceID string) error
	DeleteRAGChunksBySubjectID(ctx context.Context, subjectID int) error
	DeleteAllRAGChunks(ctx context.Context) error
	ListRAGChunksForSearch(ctx context.Context, sourceType string) ([]store.RAGChunkRow, error)
	CountRAGChunks(ctx context.Context) (int, error)
}

// WikiReader 读取 Wiki 与内容用于分块。
type WikiReader interface {
	GetWikiGraph(ctx context.Context, rootID, depth int) (*store.WikiGraphData, error)
	GetWikiSubjectByID(ctx context.Context, id int) (*store.WikiSubjectDetail, error)
	ListWikiSubjects(ctx context.Context, q store.WikiSubjectQuery) ([]store.WikiSubject, int, error)
	GetContent(ctx context.Context, kind string, id int, viewer int, admin bool) (*store.Content, error)
	ListContent(ctx context.Context, q store.ContentQuery) ([]store.Content, int, error)
}

// Service 编排分块、嵌入与检索。
type Service struct {
	indexer  Indexer
	wiki     WikiReader
	embedder EmbeddingProvider
	chat     *OpenAIChatClient
	logMu    sync.Mutex
}

func NewService(indexer Indexer, wiki WikiReader, embedder EmbeddingProvider) *Service {
	if embedder == nil {
		embedder = NewEmbeddingProviderFromEnv()
	}
	svc := &Service{indexer: indexer, wiki: wiki, embedder: embedder, chat: NewChatClientFromEnv()}
	store.SetRAGContentIngestHook(func(ctx context.Context, kind string, id int) {
		svc.IndexContentAsync(ctx, kind, id)
	})
	return svc
}

func (s *Service) EmbedderName() string {
	if s.embedder == nil {
		return "none"
	}
	return s.embedder.Name()
}

// ChatConfigured 报告是否配置了对话模型（OPENAI_API_KEY）。
// 未配置时 Ask 无法生成自然语言答案，调用方应降级为纯检索模式。
func (s *Service) ChatConfigured() bool {
	return s.chat != nil && s.chat.apiKey != ""
}

// RebuildAll 全量重建索引（管理员一键）。
func (s *Service) RebuildAll(ctx context.Context) (int, error) {
	if s.indexer == nil {
		return 0, fmt.Errorf("RAG 索引器未配置")
	}
	if err := s.indexer.DeleteAllRAGChunks(ctx); err != nil {
		return 0, err
	}
	total := 0
	page := 1
	for {
		list, count, err := s.wiki.ListWikiSubjects(ctx, store.WikiSubjectQuery{Page: page, PageSize: 50})
		if err != nil {
			return total, err
		}
		for _, sub := range list {
			n, err := s.IndexWikiSubject(ctx, sub.ID)
			if err != nil {
				s.logf("wiki subject %d index failed: %v", sub.ID, err)
				continue
			}
			total += n
		}
		if page*50 >= count || len(list) == 0 {
			break
		}
		page++
	}
	for _, kind := range []string{SourceNews, SourcePost} {
		page = 1
		for {
			items, cnt, err := s.wiki.ListContent(ctx, store.ContentQuery{
				Page: page, PageSize: 50, Kind: kind, Status: "published", Admin: true,
			})
			if err != nil {
				return total, err
			}
			for _, c := range items {
				n, err := s.IndexContent(ctx, c.Kind, c.ID)
				if err != nil {
					s.logf("content %s:%d index failed: %v", c.Kind, c.ID, err)
					continue
				}
				total += n
			}
			if page*50 >= cnt || len(items) == 0 {
				break
			}
			page++
		}
	}
	return total, nil
}

// IndexWikiSubject 对单个词条及其关系重新分块并嵌入。
func (s *Service) IndexWikiSubject(ctx context.Context, subjectID int) (int, error) {
	if subjectID <= 0 || s.indexer == nil {
		return 0, nil
	}
	detail, err := s.wiki.GetWikiSubjectByID(ctx, subjectID)
	if err != nil {
		return 0, err
	}
	_ = s.indexer.DeleteRAGChunksBySubjectID(ctx, subjectID)
	chunks := BuildWikiSubjectChunks(detail)
	chunks = append(chunks, BuildWikiRelationChunks(detail)...)
	if len(chunks) == 0 {
		return 0, nil
	}
	return s.persistChunks(ctx, chunks)
}

// RemoveWikiSubject 删除词条相关向量。
func (s *Service) RemoveWikiSubject(ctx context.Context, subjectID int) error {
	if s.indexer == nil || subjectID <= 0 {
		return nil
	}
	return s.indexer.DeleteRAGChunksBySubjectID(ctx, subjectID)
}

// IndexWikiSubjects 批量重索引（关系变更时两端词条）。
func (s *Service) IndexWikiSubjects(ctx context.Context, ids ...int) {
	for _, id := range ids {
		if id <= 0 {
			continue
		}
		if _, err := s.IndexWikiSubject(ctx, id); err != nil {
			s.logf("reindex wiki %d: %v", id, err)
		}
	}
}

func (s *Service) IndexWikiSubjectsAsync(ids ...int) {
	go s.IndexWikiSubjects(context.Background(), ids...)
}

// IndexWikiNeighborhoodAsync also indexes people and relations created by sync-video.
func (s *Service) IndexWikiNeighborhoodAsync(subjectID int) {
	go func() {
		ctx := context.Background()
		ids := []int{subjectID}
		graph, err := s.wiki.GetWikiGraph(ctx, subjectID, 1)
		if err != nil {
			s.logf("wiki neighborhood %d: %v", subjectID, err)
		} else if graph != nil {
			for _, node := range graph.Nodes {
				if node.ID != subjectID {
					ids = append(ids, node.ID)
				}
			}
		}
		s.IndexWikiSubjects(ctx, ids...)
	}()
}

func (s *Service) RemoveWikiSubjectAsync(subjectID int, neighbors ...int) {
	go func() {
		ctx := context.Background()
		if err := s.RemoveWikiSubject(ctx, subjectID); err != nil {
			s.logf("remove wiki %d: %v", subjectID, err)
		}
		s.IndexWikiSubjects(ctx, neighbors...)
	}()
}

// IndexContent 索引资讯或帖子正文。
func (s *Service) IndexContent(ctx context.Context, kind string, contentID int) (int, error) {
	if contentID <= 0 || s.indexer == nil {
		return 0, nil
	}
	c, err := s.wiki.GetContent(ctx, kind, contentID, 0, true)
	if errors.Is(err, store.ErrContentNotFound) {
		return 0, s.indexer.DeleteRAGChunksBySource(ctx, kind, fmt.Sprintf("%d", contentID))
	}
	if err != nil || c == nil {
		return 0, err
	}
	if c.Status != "published" {
		sourceType := SourceNews
		if kind == "post" {
			sourceType = SourcePost
		}
		return 0, s.indexer.DeleteRAGChunksBySource(ctx, sourceType, fmt.Sprintf("%d", contentID))
	}
	chunks := BuildContentChunks(c)
	if len(chunks) == 0 {
		return 0, nil
	}
	return s.persistChunks(ctx, chunks)
}

func (s *Service) IndexContentAsync(ctx context.Context, kind string, contentID int) {
	go func() {
		if _, err := s.IndexContent(context.Background(), kind, contentID); err != nil {
			s.logf("async content index %s:%d: %v", kind, contentID, err)
		}
	}()
}

func (s *Service) IndexWikiSubjectAsync(ctx context.Context, subjectID int) {
	go func() {
		if _, err := s.IndexWikiSubject(context.Background(), subjectID); err != nil {
			s.logf("async wiki index %d: %v", subjectID, err)
		}
	}()
}

func (s *Service) persistChunks(ctx context.Context, chunks []DocumentChunk) (int, error) {
	if len(chunks) == 0 {
		return 0, nil
	}
	// 按 source 分组写入（关系块与主体块 source_id 不同）
	groups := map[string][]DocumentChunk{}
	for _, c := range chunks {
		key := c.SourceType + "\x00" + c.SourceID
		groups[key] = append(groups[key], c)
	}
	written := 0
	for _, group := range groups {
		texts := make([]string, len(group))
		for i, c := range group {
			texts[i] = c.Text
		}
		vectors, err := s.embedder.Embed(ctx, texts)
		if err != nil {
			return written, err
		}
		rows := make([]store.RAGChunkRow, len(group))
		for i, c := range group {
			vec := vectors[i]
			rows[i] = store.RAGChunkRow{
				SourceType: c.SourceType,
				SourceID:   c.SourceID,
				SubjectID:  c.SubjectID,
				ChunkIndex: c.ChunkIndex,
				Text:       c.Text,
				Metadata:   c.Metadata,
				Embedding:  EncodeFloat32Slice(vec),
				Dimensions: len(vec),
			}
		}
		if err := s.indexer.ReplaceRAGChunks(ctx, group[0].SourceType, group[0].SourceID, rows); err != nil {
			return written, err
		}
		written += len(rows)
	}
	return written, nil
}

// Search 向量相似度检索（本地默认全表扫描 + 余弦相似度）。
// 在向量分数上叠加轻量 bigram 重叠加成（混合检索），
// 使短查询（作品名+疑问词）在伪向量模式下也能命中正确实体，远程嵌入下同样有益。
func (s *Service) Search(ctx context.Context, query string, topK int, sourceType string) (*SearchResponse, error) {
	query = stringsTrim(query)
	if query == "" {
		return nil, fmt.Errorf("查询文本不能为空")
	}
	if topK <= 0 {
		topK = 8
	}
	if topK > 50 {
		topK = 50
	}
	vecs, err := s.embedder.Embed(ctx, []string{query})
	if err != nil {
		return nil, err
	}
	qvec := vecs[0]
	qBigrams := textBigrams(query)
	rows, err := s.indexer.ListRAGChunksForSearch(ctx, sourceType)
	if err != nil {
		return nil, err
	}
	hits := make([]StoredChunk, 0, len(rows))
	for _, row := range rows {
		vec := DecodeFloat32Slice(row.Embedding, row.Dimensions)
		sim := CosineSimilarity(qvec, vec) + hybridBoost(qBigrams, row.Text)
		if sim > 1 {
			sim = 1
		}
		hits = append(hits, StoredChunk{
			ID:         row.ID,
			SourceType: row.SourceType,
			SourceID:   row.SourceID,
			SubjectID:  row.SubjectID,
			ChunkIndex: row.ChunkIndex,
			Text:       row.Text,
			Metadata:   row.Metadata,
			Similarity: sim,
		})
	}
	sortHits(hits)
	if len(hits) > topK {
		hits = hits[:topK]
	}
	return &SearchResponse{Query: query, TopK: topK, Results: hits}, nil
}

// textBigrams 提取去除空白后的字符二元组集合。
func textBigrams(s string) map[string]struct{} {
	runes := []rune(strings.ToLower(s))
	set := make(map[string]struct{}, len(runes))
	for i := 0; i+1 < len(runes); i++ {
		if unicode.IsSpace(runes[i]) || unicode.IsSpace(runes[i+1]) {
			continue
		}
		set[string(runes[i:i+2])] = struct{}{}
	}
	return set
}

// hybridBoost 依据查询与文本的 bigram 覆盖率给出加成分数（最高 0.3）。
func hybridBoost(queryBigrams map[string]struct{}, text string) float64 {
	if len(queryBigrams) == 0 {
		return 0
	}
	tb := textBigrams(text)
	overlap := 0
	for b := range queryBigrams {
		if _, ok := tb[b]; ok {
			overlap++
		}
	}
	return 0.3 * (float64(overlap) / float64(len(queryBigrams)))
}

func sortHits(hits []StoredChunk) {
	for i := 0; i < len(hits); i++ {
		for j := i + 1; j < len(hits); j++ {
			if hits[j].Similarity > hits[i].Similarity {
				hits[i], hits[j] = hits[j], hits[i]
			}
		}
	}
}

func (s *Service) logf(format string, args ...any) {
	s.logMu.Lock()
	defer s.logMu.Unlock()
	log.Printf("[rag] "+format, args...)
}

func stringsTrim(s string) string { return strings.TrimSpace(s) }
