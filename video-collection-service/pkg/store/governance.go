package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"
)

func IsStaff(role string) bool {
	return role == "super_admin" || role == "admin" || role == "observer" || role == "operator"
}
func CanReview(role string) bool { return role == "super_admin" || role == "admin" }
func ValidRole(role string) bool { return role == "user" || IsStaff(role) }

var ErrConflict = errors.New("记录已处理或内容已变更，请刷新后重新提交")
var ErrInvalidOperation = errors.New("参数或状态无效")

type Review struct {
	ID            int             `json:"id"`
	Kind          string          `json:"kind"`
	TargetID      int             `json:"target_id"`
	SubmitterID   int             `json:"submitter_id"`
	SubmitterName string          `json:"submitter_name"`
	Payload       json.RawMessage `json:"payload"`
	Baseline      string          `json:"-"`
	Status        string          `json:"status"`
	ReviewerID    int             `json:"reviewer_id"`
	Note          string          `json:"note"`
	CreatedAt     string          `json:"created_at"`
	UpdatedAt     string          `json:"updated_at"`
}

type GovernanceStore interface {
	RecordAdminOperation(context.Context, int, string, string, int) error
	ListAdminOperations(context.Context, int, int) ([]AdminOperation, int, error)
	ManageUser(context.Context, int, *User, bool) error
	SubmitReview(context.Context, *Review) error
	ListReviews(context.Context, int, string, int, int) ([]Review, int, error)
	DecideReview(context.Context, int, int, bool, string) error
	SaveVideoAtomic(context.Context, *VideoRecord) (int, error)
}

type AdminOperation struct {
	ID        int    `json:"id"`
	ActorID   int    `json:"actor_id"`
	Username  string `json:"username"`
	Method    string `json:"method"`
	Path      string `json:"path"`
	Status    int    `json:"status"`
	CreatedAt string `json:"created_at"`
}

func (s *SQLContentStore) RecordAdminOperation(ctx context.Context, actor int, method, path string, status int) error {
	_, err := s.db.ExecContext(ctx, "INSERT INTO admin_operations(actor_id,method,path,status,created_at) VALUES($1,$2,$3,$4,$5)", actor, method, path, status, time.Now().UTC().Format(time.RFC3339Nano))
	return err
}
func (s *SQLContentStore) ListAdminOperations(ctx context.Context, page, size int) ([]AdminOperation, int, error) {
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM admin_operations").Scan(&total); err != nil {
		return nil, 0, err
	}
	limit, offset := contentPage(page, size)
	rows, err := s.db.QueryContext(ctx, "SELECT o.id,o.actor_id,COALESCE(u.username,''),o.method,o.path,o.status,o.created_at FROM admin_operations o LEFT JOIN users u ON u.id=o.actor_id ORDER BY o.id DESC LIMIT $1 OFFSET $2", limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := []AdminOperation{}
	for rows.Next() {
		var v AdminOperation
		if err = rows.Scan(&v.ID, &v.ActorID, &v.Username, &v.Method, &v.Path, &v.Status, &v.CreatedAt); err != nil {
			return nil, 0, err
		}
		items = append(items, v)
	}
	return items, total, rows.Err()
}

// All account changes serialize on a single row, preventing two administrators
// from simultaneously removing the final enabled super administrator.
func (s *SQLContentStore) ManageUser(ctx context.Context, actor int, u *User, remove bool) error {
	if !ValidRole(u.Role) || (u.Status != 0 && u.Status != 1) {
		return ErrInvalidOperation
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, "UPDATE governance_guard SET id=id WHERE id=1"); err != nil {
		return err
	}
	var role string
	if err = tx.QueryRowContext(ctx, "SELECT role FROM users WHERE id=$1 AND status=1", actor).Scan(&role); err != nil {
		return ErrContentForbidden
	}
	if !CanReview(role) {
		return ErrContentForbidden
	}
	oldRole := "user"
	if u.ID > 0 {
		if err = tx.QueryRowContext(ctx, "SELECT role FROM users WHERE id=$1", u.ID).Scan(&oldRole); err != nil {
			return ErrContentNotFound
		}
	}
	if role != "super_admin" && (oldRole != "user" || u.Role != "user") {
		return ErrContentForbidden
	}
	if u.ID == actor && (remove || u.Role != role || u.Status != 1) {
		return ErrContentForbidden
	}
	if oldRole == "super_admin" && (remove || u.Role != oldRole || u.Status == 0) {
		var count int
		if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM users WHERE role='super_admin' AND status=1 AND id<>$1", u.ID).Scan(&count); err != nil {
			return err
		}
		if count == 0 {
			return fmt.Errorf("必须保留至少一名正常的超级管理员: %w", ErrInvalidOperation)
		}
	}
	if remove {
		_, err = tx.ExecContext(ctx, "DELETE FROM users WHERE id=$1", u.ID)
	} else if u.ID > 0 {
		_, err = tx.ExecContext(ctx, `UPDATE users SET nickname=$1,role=$2,status=$3,password_hash=$4,updated_at=$5 WHERE id=$6`, u.Nickname, u.Role, u.Status, u.PasswordHash, time.Now().UTC(), u.ID)
	} else {
		err = tx.QueryRowContext(ctx, `INSERT INTO users(username,password_hash,nickname,role,status) VALUES($1,$2,$3,$4,$5) RETURNING id`, u.Username, u.PasswordHash, u.Nickname, u.Role, u.Status).Scan(&u.ID)
	}
	if err != nil {
		return err
	}
	return tx.Commit()
}

func notifyAdmins(ctx context.Context, tx *sql.Tx, actor int, title, body, kind string, id int) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO user_notifications(user_id,actor_id,type,title,content,target_type,target_id,created_at)
 SELECT id,$1,'system',$2,$3,$4,$5,$6 FROM users WHERE role IN ('admin','super_admin') AND status=1`, actor, title, body, kind, id, time.Now().UTC())
	return err
}

func reviewBaseline(ctx context.Context, tx *sql.Tx, kind string, id int) (string, error) {
	if id == 0 {
		return "", nil
	}
	var updated time.Time
	var err error
	if kind == "video" {
		err = tx.QueryRowContext(ctx, "UPDATE videos SET id=id WHERE id=$1 RETURNING updated_at", id).Scan(&updated)
	} else {
		err = tx.QueryRowContext(ctx, "UPDATE content_entries SET id=id WHERE id=$1 AND kind=$2 RETURNING updated_at", id, kind).Scan(&updated)
	}
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrContentNotFound
	}
	return updated.UTC().Format(time.RFC3339Nano), err
}

func (s *SQLContentStore) SubmitReview(ctx context.Context, v *Review) error {
	if v.Kind != "video" && v.Kind != "news" && v.Kind != "post" && v.Kind != "comment" {
		return ErrInvalidOperation
	}
	if v.TargetID < 0 || len(v.Payload) > 1<<20 || !json.Valid(v.Payload) {
		return ErrInvalidOperation
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var role string
	if err = tx.QueryRowContext(ctx, "UPDATE users SET id=id WHERE id=$1 AND status=1 RETURNING role", v.SubmitterID).Scan(&role); err != nil || role != "operator" {
		return ErrContentForbidden
	}
	if v.Kind == "comment" {
		var c Comment
		if json.Unmarshal(v.Payload, &c) != nil || c.UserID != v.SubmitterID || c.ParentID < 0 || strings.TrimSpace(c.Content) == "" || utf8.RuneCountInString(c.Content) > 2000 {
			return ErrInvalidComment
		}
		if _, err = s.commentTarget(ctx, tx, c.TargetType, c.TargetID, true, false); err != nil {
			return err
		}
	} else if v.Baseline, err = reviewBaseline(ctx, tx, v.Kind, v.TargetID); err != nil {
		return err
	}
	v.CreatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	v.UpdatedAt = v.CreatedAt
	v.Status = "pending"
	err = tx.QueryRowContext(ctx, `INSERT INTO content_reviews(kind,target_id,submitter_id,payload,baseline,status,created_at,updated_at) VALUES($1,$2,$3,$4,$5,'pending',$6,$6) RETURNING id`, v.Kind, v.TargetID, v.SubmitterID, string(v.Payload), v.Baseline, v.CreatedAt).Scan(&v.ID)
	if err != nil {
		return err
	}
	if err = notifyAdmins(ctx, tx, v.SubmitterID, "有新的运营内容待审核", v.Kind, "review", v.ID); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *SQLContentStore) ListReviews(ctx context.Context, owner int, status string, page, size int) ([]Review, int, error) {
	if status != "" && status != "pending" && status != "approved" && status != "rejected" {
		return nil, 0, ErrInvalidOperation
	}
	where := " WHERE ($1=0 OR r.submitter_id=$1) AND ($2='' OR r.status=$2)"
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM content_reviews r"+where, owner, status).Scan(&total); err != nil {
		return nil, 0, err
	}
	limit, offset := contentPage(page, size)
	rows, err := s.db.QueryContext(ctx, `SELECT r.id,r.kind,r.target_id,r.submitter_id,COALESCE(NULLIF(u.nickname,''),u.username,''),r.payload,r.status,r.reviewer_id,r.note,r.created_at,r.updated_at FROM content_reviews r LEFT JOIN users u ON u.id=r.submitter_id`+where+" ORDER BY r.id DESC LIMIT $3 OFFSET $4", owner, status, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := []Review{}
	for rows.Next() {
		var v Review
		var payload string
		if err = rows.Scan(&v.ID, &v.Kind, &v.TargetID, &v.SubmitterID, &v.SubmitterName, &payload, &v.Status, &v.ReviewerID, &v.Note, &v.CreatedAt, &v.UpdatedAt); err != nil {
			return nil, 0, err
		}
		v.Payload = json.RawMessage(payload)
		items = append(items, v)
	}
	return items, total, rows.Err()
}

func (s *SQLContentStore) DecideReview(ctx context.Context, id, actor int, approve bool, note string) error {
	if utf8.RuneCountInString(note) > 1000 || (!approve && strings.TrimSpace(note) == "") {
		return ErrInvalidOperation
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var role string
	if err = tx.QueryRowContext(ctx, "SELECT role FROM users WHERE id=$1 AND status=1", actor).Scan(&role); err != nil || !CanReview(role) {
		return ErrContentForbidden
	}
	var v Review
	var payload string
	err = tx.QueryRowContext(ctx, `UPDATE content_reviews SET id=id WHERE id=$1 AND status='pending' RETURNING kind,target_id,submitter_id,payload,baseline`, id).Scan(&v.Kind, &v.TargetID, &v.SubmitterID, &payload, &v.Baseline)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrConflict
	}
	if err != nil {
		return err
	}
	if actor == v.SubmitterID {
		return ErrContentForbidden
	}
	state := "rejected"
	if approve {
		var active int
		if err = tx.QueryRowContext(ctx, "SELECT status FROM users WHERE id=$1", v.SubmitterID).Scan(&active); err != nil || active != 1 {
			return ErrContentForbidden
		}
		if v.Kind != "comment" {
			baseline, e := reviewBaseline(ctx, tx, v.Kind, v.TargetID)
			if e != nil {
				return e
			}
			if baseline != v.Baseline {
				return ErrConflict
			}
		}
		switch v.Kind {
		case "video":
			var c VideoRecord
			if err = json.Unmarshal([]byte(payload), &c); err == nil {
				c.ID = v.TargetID
				err = s.saveVideoTx(ctx, tx, &c)
				v.TargetID = c.ID
			}
		case "news", "post":
			var c Content
			if err = json.Unmarshal([]byte(payload), &c); err == nil {
				c.Kind = v.Kind
				c.ID = v.TargetID
				err = saveContentTx(ctx, tx, &c, v.SubmitterID, true)
				v.TargetID = c.ID
			}
		case "comment":
			var c Comment
			if err = json.Unmarshal([]byte(payload), &c); err == nil {
				c.UserID = v.SubmitterID
				err = s.addCommentTx(ctx, tx, &c)
				v.TargetID = c.ID
			}
		default:
			return ErrInvalidOperation
		}
		if err != nil {
			return err
		}
		state = "approved"
	}
	if _, err = tx.ExecContext(ctx, "UPDATE content_reviews SET status=$1,reviewer_id=$2,note=$3,target_id=$4,updated_at=$5 WHERE id=$6", state, actor, note, v.TargetID, time.Now().UTC().Format(time.RFC3339Nano), id); err != nil {
		return err
	}
	statusLabel := "已拒绝"
	if approve {
		statusLabel = "已通过"
	}
	if err = insertNotification(ctx, tx, &Notification{UserID: v.SubmitterID, ActorID: actor, Type: "system", Title: "内容审核结果：" + statusLabel, Content: note, TargetType: "review", TargetID: id}); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *SQLContentStore) SaveVideoAtomic(ctx context.Context, v *VideoRecord) (int, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	if err = s.saveVideoTx(ctx, tx, v); err != nil {
		return 0, err
	}
	return v.ID, tx.Commit()
}

func (s *SQLContentStore) saveVideoTx(ctx context.Context, tx *sql.Tx, v *VideoRecord) error {
	if v.ID < 0 || strings.TrimSpace(v.Name) == "" || utf8.RuneCountInString(v.Name) > 200 {
		return ErrInvalidOperation
	}
	if v.Picture == "" {
		v.Picture = v.Pic
	}
	if len(v.PlayGroups) == 0 {
		v.PlayGroups = v.PlayRoutes
	}
	now := time.Now().UTC()
	if v.TypeID > 0 && v.TypeName == "" {
		_ = tx.QueryRowContext(ctx, "SELECT name FROM categories WHERE id=$1", v.TypeID).Scan(&v.TypeName)
	}
	args := []any{v.Name, v.SubName, v.TypeID, v.TypeName, v.Picture, v.Actor, v.Director, v.Area, v.Language, v.Year, v.Remarks, v.Content, now}
	if v.ID == 0 {
		args = append(args, v.SourceID)
		err := tx.QueryRowContext(ctx, `INSERT INTO videos(name,sub_name,type_id,type_name,picture,actor,director,area,language,year,remarks,content,created_at,updated_at,source_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13,$14) RETURNING id`, args...).Scan(&v.ID)
		if err != nil {
			return err
		}
	} else {
		args = append(args, v.ID)
		res, err := tx.ExecContext(ctx, `UPDATE videos SET name=$1,sub_name=$2,type_id=$3,type_name=$4,picture=$5,actor=$6,director=$7,area=$8,language=$9,year=$10,remarks=$11,content=$12,updated_at=$13 WHERE id=$14`, args...)
		if err != nil {
			return err
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			return ErrContentNotFound
		}
	}
	if s.postgres {
		data, err := json.Marshal(v.PlayGroups)
		if err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, "UPDATE videos SET play_groups=$1::jsonb WHERE id=$2", string(data), v.ID)
		return err
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM play_sources WHERE video_id=$1", v.ID); err != nil {
		return err
	}
	for _, pg := range v.PlayGroups {
		data, err := json.Marshal(pg.Episodes)
		if err != nil {
			return err
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO play_sources(video_id,player_code,server,note,episodes,updated_at) VALUES($1,$2,$3,$4,$5,$6)`, v.ID, pg.PlayerCode, pg.Server, pg.Note, string(data), now); err != nil {
			return fmt.Errorf("保存播放线路: %w", err)
		}
	}
	return nil
}
