package api

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"video-collection-api/pkg/store"
)

// dbAdminStore 获取当前存储实现上的数据库管理能力
func (srv *Server) dbAdmin() (store.DBAdmin, bool) {
	admin, ok := srv.store.(store.DBAdmin)
	return admin, ok
}

// handleDBInfo 数据库整体信息
func (srv *Server) handleDBInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	admin, ok := srv.dbAdmin()
	if !ok {
		errorResponse(w, http.StatusNotImplemented, "当前存储实现不支持数据库管理")
		return
	}
	info, err := admin.GetDBInfo(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": info})
}

// handleDBTables 数据表列表与统计
func (srv *Server) handleDBTables(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	admin, ok := srv.dbAdmin()
	if !ok {
		errorResponse(w, http.StatusNotImplemented, "当前存储实现不支持数据库管理")
		return
	}
	tables, err := admin.ListDBTables(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	if tables == nil {
		tables = []store.DBTableInfo{}
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": tables})
}

// handleDBTable 浏览指定表的数据（分页 / 排序 / 全列模糊搜索）
func (srv *Server) handleDBTable(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	admin, ok := srv.dbAdmin()
	if !ok {
		errorResponse(w, http.StatusNotImplemented, "当前存储实现不支持数据库管理")
		return
	}
	q := r.URL.Query()
	page, _ := strconv.Atoi(q.Get("page"))
	if page <= 0 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(q.Get("page_size"))
	if pageSize <= 0 || pageSize > 500 {
		pageSize = 100
	}
	result, err := admin.BrowseTable(r.Context(), store.TableBrowseQuery{
		Table:     strings.TrimSpace(q.Get("table")),
		Page:      page,
		PageSize:  pageSize,
		OrderBy:   strings.TrimSpace(q.Get("order_by")),
		OrderDesc: q.Get("order_desc") == "1" || q.Get("order_desc") == "true" || q.Get("order_dir") == "desc",
		Keyword:   strings.TrimSpace(q.Get("keyword")),
	})
	if err != nil {
		errorResponse(w, http.StatusBadRequest, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": result})
}

// handleDBBackup 创建数据库备份（可选指定数据表，默认全部业务表）
func (srv *Server) handleDBBackup(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	admin, ok := srv.dbAdmin()
	if !ok {
		errorResponse(w, http.StatusNotImplemented, "当前存储实现不支持数据库管理")
		return
	}
	var req store.BackupOptions
	_ = json.NewDecoder(r.Body).Decode(&req)
	result, err := admin.BackupDatabase(r.Context(), req)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  "数据库备份已创建",
		"data": result,
	})
}

// handleDBBackups 备份文件列表 / 删除备份（删除需 confirm=1）
func (srv *Server) handleDBBackups(w http.ResponseWriter, r *http.Request) {
	admin, ok := srv.dbAdmin()
	if !ok {
		errorResponse(w, http.StatusNotImplemented, "当前存储实现不支持数据库管理")
		return
	}
	switch r.Method {
	case http.MethodGet:
		list, err := admin.ListBackups(r.Context())
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		if list == nil {
			list = []store.BackupMeta{}
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": list})
	case http.MethodDelete:
		file := strings.TrimSpace(r.URL.Query().Get("file"))
		if file == "" {
			errorResponse(w, http.StatusBadRequest, "缺少 file 参数")
			return
		}
		if r.URL.Query().Get("confirm") != "1" {
			errorResponse(w, http.StatusBadRequest, "删除备份为不可恢复操作，请携带 confirm=1 确认")
			return
		}
		if err := admin.DeleteBackup(r.Context(), file); err != nil {
			errorResponse(w, http.StatusBadRequest, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "备份文件已删除"})
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// handleDBRestore 从备份恢复数据
// mode=merge 合并导入；mode=replace 清空目标表后导入（危险）。
// dry_run=true 仅返回预览；正式执行需 confirm=true。
func (srv *Server) handleDBRestore(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	admin, ok := srv.dbAdmin()
	if !ok {
		errorResponse(w, http.StatusNotImplemented, "当前存储实现不支持数据库管理")
		return
	}
	var req struct {
		File    string `json:"file"`
		Mode    string `json:"mode"`
		DryRun  bool   `json:"dry_run"`
		Confirm bool   `json:"confirm"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析失败: "+err.Error())
		return
	}
	req.File = strings.TrimSpace(req.File)
	if req.File == "" {
		errorResponse(w, http.StatusBadRequest, "缺少 file 参数")
		return
	}
	if req.Mode == "" {
		req.Mode = "merge"
	}
	if req.Mode != "merge" && req.Mode != "replace" {
		errorResponse(w, http.StatusBadRequest, "mode 仅支持 merge / replace")
		return
	}

	if req.DryRun {
		preview, err := admin.PreviewRestore(r.Context(), req.File, req.Mode)
		if err != nil {
			errorResponse(w, http.StatusBadRequest, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": preview})
		return
	}

	if !req.Confirm {
		msg := "恢复操作为不可逆数据写入"
		if req.Mode == "replace" {
			msg += "（replace 模式会清空目标表）"
		}
		errorResponse(w, http.StatusBadRequest, msg+", 请先使用 dry_run 预览并携带 confirm=true 确认执行")
		return
	}

	result, err := admin.RestoreDatabase(r.Context(), req.File, req.Mode)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "数据恢复完成", "data": result})
}

// handleDBCleanup 数据清理维护
// actions 支持: vacuum / orphan_play_sources / dup_play_sources / orphan_comments /
// orphan_user_history / orphan_user_favorites / clear_user_history / clear_feedbacks
// 写操作需携带 confirm=true 确认。
func (srv *Server) handleDBCleanup(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	admin, ok := srv.dbAdmin()
	if !ok {
		errorResponse(w, http.StatusNotImplemented, "当前存储实现不支持数据库管理")
		return
	}
	var req struct {
		Actions []string `json:"actions"`
		Confirm bool     `json:"confirm"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析失败: "+err.Error())
		return
	}
	if len(req.Actions) == 0 {
		errorResponse(w, http.StatusBadRequest, "请选择要执行的清理动作")
		return
	}
	if !req.Confirm {
		errorResponse(w, http.StatusBadRequest, "清理动作将直接删除数据，请携带 confirm=true 确认执行")
		return
	}
	results, err := admin.RunCleanup(r.Context(), req.Actions)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": results})
}

// handleDBSQL 执行管理 SQL
// SELECT / WITH / SHOW / EXPLAIN / PRAGMA 等只读语句直接执行（最多返回 1000 行）；
// INSERT / UPDATE / DELETE 与 DDL 语句需携带 confirm=true 确认。
func (srv *Server) handleDBSQL(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	admin, ok := srv.dbAdmin()
	if !ok {
		errorResponse(w, http.StatusNotImplemented, "当前存储实现不支持数据库管理")
		return
	}
	var req struct {
		SQL     string `json:"sql"`
		Confirm bool   `json:"confirm"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析失败: "+err.Error())
		return
	}
	req.SQL = strings.TrimSpace(req.SQL)
	if req.SQL == "" {
		errorResponse(w, http.StatusBadRequest, "SQL 不能为空")
		return
	}
	if !store.IsSingleStatement(req.SQL) {
		errorResponse(w, http.StatusBadRequest, "仅支持单条 SQL 语句，不允许分号分隔多条")
		return
	}

	sqlType := store.ClassifySQL(req.SQL)
	if (sqlType == "write" || sqlType == "ddl") && !req.Confirm {
		errorResponse(w, http.StatusBadRequest, "检测到"+sqlTypeName(sqlType)+"语句，执行将修改数据库数据，请携带 confirm=true 确认")
		return
	}

	result, err := admin.ExecSQL(r.Context(), req.SQL)
	if err != nil {
		errorResponse(w, http.StatusBadRequest, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": result})
}

func sqlTypeName(t string) string {
	if t == "write" {
		return "写"
	}
	return "DDL"
}