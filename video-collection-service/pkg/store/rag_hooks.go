package store

import "context"

// onRAGContentIngest 由 RAG 服务在启动时注册，避免 store ↔ rag 循环依赖。
var onRAGContentIngest func(context.Context, string, int)

// SetRAGContentIngestHook 注册采集文章入库后的索引回调。
func SetRAGContentIngestHook(fn func(context.Context, string, int)) {
	onRAGContentIngest = fn
}

func notifyRAGContentIngest(ctx context.Context, kind string, contentID int) {
	if onRAGContentIngest == nil || contentID <= 0 {
		return
	}
	onRAGContentIngest(ctx, kind, contentID)
}
