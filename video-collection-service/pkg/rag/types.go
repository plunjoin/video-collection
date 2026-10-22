package rag

// SourceType 标识向量块来源，便于 LLM RAG 引用与过滤。
const (
	SourceWikiSubject  = "wiki_subject"
	SourceWikiRelation = "wiki_relation"
	SourceNews         = "news"
	SourcePost         = "post"
)

// DocumentChunk 待写入向量库的文本块（尚未嵌入）。
type DocumentChunk struct {
	SourceType string
	SourceID   string
	SubjectID  int
	ChunkIndex int
	Text       string
	Metadata   map[string]any
}

// StoredChunk 已持久化并带相似度的检索结果。
type StoredChunk struct {
	ID         int64          `json:"id"`
	SourceType string         `json:"source_type"`
	SourceID   string         `json:"source_id"`
	SubjectID  int            `json:"subject_id"`
	ChunkIndex int            `json:"chunk_index"`
	Text       string         `json:"text"`
	Metadata   map[string]any `json:"metadata"`
	Similarity float64        `json:"similarity"`
}

// SearchResponse 面向未来 LLM 编排的检索响应形状。
type SearchResponse struct {
	Query   string        `json:"query"`
	TopK    int           `json:"top_k"`
	Results []StoredChunk `json:"results"`
}

// AskResponse includes the exact retrieved chunks used as numbered citations.
type AskResponse struct {
	Query     string        `json:"query"`
	Answer    string        `json:"answer"`
	Citations []StoredChunk `json:"citations"`
	Model     string        `json:"model"`
	Embedder  string        `json:"embedder"`
	TopK      int           `json:"top_k"`
	GraphNote string        `json:"graph_note,omitempty"`
}
