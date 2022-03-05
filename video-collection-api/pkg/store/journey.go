package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

type GrowthMission struct {
	Key         string `json:"key"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Kind        string `json:"kind"`
	Period      string `json:"period"`
	Target      int    `json:"target"`
	Reward      int    `json:"reward"`
	Active      bool   `json:"active"`
	Progress    int    `json:"progress"`
	Claimed     bool   `json:"claimed"`
	Href        string `json:"href"`
}
type GrowthLevel struct {
	Level     int    `json:"level"`
	Name      string `json:"name"`
	Threshold int    `json:"threshold"`
}
type JourneyStore interface {
	Journey(context.Context, int) (map[string]any, error)
	ListGrowthMissions(context.Context, int, bool, time.Time) ([]GrowthMission, error)
	SaveGrowthMission(context.Context, *GrowthMission) error
	ClaimGrowthMission(context.Context, int, string, time.Time) (int, error)
	ShareMovieRequest(context.Context, int, int, bool) error
	SupportMovieRequest(context.Context, int, int) error
	MovieRequestWall(context.Context, int, int, int) ([]MovieRequest, int, error)
}

func migrateJourney(tx *sql.Tx) error {
	_, err := tx.Exec(`CREATE TABLE IF NOT EXISTS growth_missions(key TEXT PRIMARY KEY,name TEXT NOT NULL,description TEXT NOT NULL,kind TEXT NOT NULL,period TEXT NOT NULL,target INTEGER NOT NULL,reward INTEGER NOT NULL,active INTEGER NOT NULL DEFAULT 1);
 CREATE TABLE IF NOT EXISTS growth_levels(level INTEGER PRIMARY KEY,name TEXT NOT NULL,threshold INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS movie_request_shares(request_id INTEGER PRIMARY KEY REFERENCES movie_requests(id) ON DELETE CASCADE,enabled INTEGER NOT NULL DEFAULT 1);
 CREATE TABLE IF NOT EXISTS movie_request_supports(request_id INTEGER NOT NULL REFERENCES movie_requests(id) ON DELETE CASCADE,user_id INTEGER NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(request_id,user_id));
 CREATE INDEX IF NOT EXISTS idx_request_supporter ON movie_request_supports(user_id);
 INSERT INTO growth_levels(level,name,threshold) VALUES(1,'初遇故事',0),(2,'追番同好',100),(3,'故事收藏家',300),(4,'热爱领航员',800),(5,'星光守护者',2000) ON CONFLICT(level) DO NOTHING;`)
	if err != nil {
		return err
	}
	marker, err := tx.Exec("INSERT INTO content_migrations(name) VALUES('growth_journey_v1') ON CONFLICT(name) DO NOTHING")
	if err != nil {
		return err
	}
	n, err := marker.RowsAffected()
	if err != nil || n == 0 {
		return err
	}
	seeds := []GrowthMission{
		{Key: "daily_story", Name: "把故事看下去", Description: "今天同步一部作品的云端观影记录", Kind: "history", Period: "day", Target: 1, Reward: 10},
		{Key: "first_favorite", Name: "收藏第一份心动", Description: "把一部喜欢的作品加入追番收藏", Kind: "favorite", Period: "once", Target: 1, Reward: 15},
		{Key: "first_comment", Name: "留下你的声音", Description: "发布一条留言，与同好分享感受", Kind: "comment", Period: "once", Target: 1, Reward: 20},
		{Key: "seven_checkins", Name: "七日相伴", Description: "完成一次连续七天签到", Kind: "checkin", Period: "once", Target: 7, Reward: 50},
		{Key: "first_support", Name: "为同好的期待亮灯", Description: "助力一个其他同好的公开求片", Kind: "support", Period: "once", Target: 1, Reward: 10},
	}
	for _, m := range seeds {
		if _, err = tx.Exec("INSERT INTO growth_missions(key,name,description,kind,period,target,reward) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(key) DO NOTHING", m.Key, m.Name, m.Description, m.Kind, m.Period, m.Target, m.Reward); err != nil {
			return err
		}
	}
	return nil
}

type journeyQuery interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func missionKey(m GrowthMission, now time.Time) string {
	key := "mission:" + m.Key + ":"
	if m.Period == "day" {
		return key + businessDay(now)
	}
	return key + "once"
}
func missionProgress(ctx context.Context, q journeyQuery, user int, m GrowthMission, now time.Time) (int, error) {
	start := time.Date(now.In(businessZone).Year(), now.In(businessZone).Month(), now.In(businessZone).Day(), 0, 0, 0, 0, businessZone).UTC()
	args := []any{user}
	where := ""
	if m.Period == "day" && m.Kind != "checkin" {
		args = append(args, start, start.AddDate(0, 0, 1))
		where = " AND %s >= $2 AND %s < $3"
	}
	query := ""
	switch m.Kind {
	case "favorite":
		query = "SELECT COUNT(*) FROM user_favorites f JOIN videos v ON v.id=f.video_id WHERE f.user_id=$1"
		if where != "" {
			query += fmt.Sprintf(where, "f.created_at", "f.created_at")
		}
	case "history":
		query = "SELECT COUNT(*) FROM user_history h JOIN videos v ON v.id=h.video_id WHERE h.user_id=$1"
		if where != "" {
			query += fmt.Sprintf(where, "h.updated_at", "h.updated_at")
		}
	case "comment":
		query = "SELECT COUNT(*) FROM comments c WHERE c.user_id=$1 AND c.is_deleted=0"
		if where != "" {
			query += fmt.Sprintf(where, "c.created_at", "c.created_at")
		}
	case "checkin":
		query = "SELECT COALESCE(MAX(streak),0) FROM daily_checkins WHERE user_id=$1"
	case "support":
		query = "SELECT COUNT(*) FROM movie_request_supports WHERE user_id=$1"
		if where != "" {
			query += fmt.Sprintf(where, "created_at", "created_at")
			args[1] = start.Format(time.RFC3339Nano)
			args[2] = start.AddDate(0, 0, 1).Format(time.RFC3339Nano)
		}
	default:
		return 0, ErrInvalidOperation
	}
	var progress int
	err := q.QueryRowContext(ctx, query, args...).Scan(&progress)
	return progress, err
}

var missionLinks = map[string]string{"history": "/follow?tab=history", "favorite": "/category", "comment": "/community", "checkin": "/points", "support": "/points?tab=wishes"}

func (s *SQLContentStore) ListGrowthMissions(ctx context.Context, user int, admin bool, now time.Time) ([]GrowthMission, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT key,name,description,kind,period,target,reward,active FROM growth_missions WHERE ($1=1 OR active=1) ORDER BY period,key", boolInt(admin))
	if err != nil {
		return nil, err
	}
	items := []GrowthMission{}
	for rows.Next() {
		var m GrowthMission
		var active int
		if err = rows.Scan(&m.Key, &m.Name, &m.Description, &m.Kind, &m.Period, &m.Target, &m.Reward, &active); err != nil {
			rows.Close()
			return nil, err
		}
		m.Active = active == 1
		m.Href = missionLinks[m.Kind]
		items = append(items, m)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if !admin {
		for i := range items {
			m := &items[i]
			if m.Progress, err = missionProgress(ctx, s.db, user, *m, now); err != nil {
				return nil, err
			}
			var count int
			if err = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM point_ledger WHERE user_id=$1 AND event_key=$2", user, missionKey(*m, now)).Scan(&count); err != nil {
				return nil, err
			}
			m.Claimed = count > 0
			if m.Progress > m.Target {
				m.Progress = m.Target
			}
		}
	}
	return items, nil
}

var missionNamePattern = regexp.MustCompile(`^[a-z][a-z0-9_]{0,39}$`)

func (s *SQLContentStore) SaveGrowthMission(ctx context.Context, m *GrowthMission) error {
	if !missionNamePattern.MatchString(m.Key) || strings.TrimSpace(m.Name) == "" || utf8.RuneCountInString(m.Name) > 40 || utf8.RuneCountInString(m.Description) > 300 || missionLinks[m.Kind] == "" || (m.Period != "once" && m.Period != "day") || (m.Kind == "checkin" && m.Period != "once") || m.Target < 1 || m.Target > 100 || m.Reward < 0 || m.Reward > 500 {
		return ErrInvalidOperation
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var kind, period string
	err = tx.QueryRowContext(ctx, "UPDATE growth_missions SET key=key WHERE key=$1 RETURNING kind,period", m.Key).Scan(&kind, &period)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if err == nil && (kind != m.Kind || period != m.Period) {
		return ErrInvalidOperation
	}
	_, err = tx.ExecContext(ctx, "INSERT INTO growth_missions(key,name,description,kind,period,target,reward,active) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(key) DO UPDATE SET name=excluded.name,description=excluded.description,target=excluded.target,reward=excluded.reward,active=excluded.active", m.Key, m.Name, m.Description, m.Kind, m.Period, m.Target, m.Reward, boolInt(m.Active))
	if err != nil {
		return err
	}
	return tx.Commit()
}
func (s *SQLContentStore) ClaimGrowthMission(ctx context.Context, user int, key string, now time.Time) (int, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	if err = lockWallet(ctx, tx, user); err != nil {
		return 0, err
	}
	var m GrowthMission
	m.Key = key
	err = tx.QueryRowContext(ctx, "UPDATE growth_missions SET key=key WHERE key=$1 AND active=1 RETURNING name,kind,period,target,reward", key).Scan(&m.Name, &m.Kind, &m.Period, &m.Target, &m.Reward)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrContentNotFound
	}
	if err != nil {
		return 0, err
	}
	var claimed int
	if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM point_ledger WHERE user_id=$1 AND event_key=$2", user, missionKey(m, now)).Scan(&claimed); err != nil {
		return 0, err
	}
	if claimed > 0 {
		return 0, tx.Commit()
	}
	progress, err := missionProgress(ctx, tx, user, m, now)
	if err != nil {
		return 0, err
	}
	if progress < m.Target {
		return 0, fmt.Errorf("任务尚未完成: %w", ErrInvalidOperation)
	}
	if err = addPoints(ctx, tx, user, m.Reward, "成长任务："+m.Name, missionKey(m, now), now); err != nil {
		return 0, err
	}
	return m.Reward, tx.Commit()
}
func (s *SQLContentStore) Journey(ctx context.Context, user int) (map[string]any, error) {
	var experience int
	if err := s.db.QueryRowContext(ctx, "SELECT COALESCE(SUM(amount),0) FROM point_ledger WHERE user_id=$1 AND amount>0 AND event_key NOT LIKE 'refund:%'", user).Scan(&experience); err != nil {
		return nil, err
	}
	rows, err := s.db.QueryContext(ctx, "SELECT level,name,threshold FROM growth_levels ORDER BY threshold")
	if err != nil {
		return nil, err
	}
	levels := []GrowthLevel{}
	for rows.Next() {
		var l GrowthLevel
		if err = rows.Scan(&l.Level, &l.Name, &l.Threshold); err != nil {
			rows.Close()
			return nil, err
		}
		levels = append(levels, l)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if len(levels) == 0 {
		return nil, ErrInvalidOperation
	}
	current := levels[0]
	var next *GrowthLevel
	for i := range levels {
		if experience >= levels[i].Threshold {
			current = levels[i]
		} else {
			next = &levels[i]
			break
		}
	}
	missions, err := s.ListGrowthMissions(ctx, user, false, time.Now())
	if err != nil {
		return nil, err
	}
	return map[string]any{"experience": experience, "level": current, "next_level": next, "levels": levels, "missions": missions}, nil
}
func (s *SQLContentStore) ShareMovieRequest(ctx context.Context, user, id int, share bool) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var owner int
	var state string
	err = tx.QueryRowContext(ctx, "UPDATE movie_requests SET id=id WHERE id=$1 RETURNING user_id,status", id).Scan(&owner, &state)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrContentNotFound
	}
	if err != nil {
		return err
	}
	if owner != user {
		return ErrContentForbidden
	}
	if share && state != "pending" && state != "processing" {
		return ErrConflict
	}
	_, err = tx.ExecContext(ctx, "INSERT INTO movie_request_shares(request_id,enabled) VALUES($1,$2) ON CONFLICT(request_id) DO UPDATE SET enabled=excluded.enabled", id, boolInt(share))
	if err != nil {
		return err
	}
	return tx.Commit()
}
func (s *SQLContentStore) SupportMovieRequest(ctx context.Context, user, id int) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var owner int
	var state string
	err = tx.QueryRowContext(ctx, "UPDATE movie_requests SET id=id WHERE id=$1 RETURNING user_id,status", id).Scan(&owner, &state)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrContentNotFound
	}
	if err != nil {
		return err
	}
	if owner == user {
		return ErrContentForbidden
	}
	if state != "pending" && state != "processing" {
		return ErrConflict
	}
	var enabled int
	err = tx.QueryRowContext(ctx, "UPDATE movie_request_shares SET enabled=enabled WHERE request_id=$1 RETURNING enabled", id).Scan(&enabled)
	if errors.Is(err, sql.ErrNoRows) || enabled != 1 {
		return ErrContentNotFound
	}
	if err != nil {
		return err
	}
	var active int
	if err = tx.QueryRowContext(ctx, "SELECT status FROM users WHERE id=$1", owner).Scan(&active); err != nil || active != 1 {
		return ErrContentNotFound
	}
	_, err = tx.ExecContext(ctx, "INSERT INTO movie_request_supports(request_id,user_id,created_at) VALUES($1,$2,$3) ON CONFLICT(request_id,user_id) DO NOTHING", id, user, time.Now().UTC().Format(time.RFC3339Nano))
	if err != nil {
		return err
	}
	return tx.Commit()
}
func (s *SQLContentStore) MovieRequestWall(ctx context.Context, user, page, size int) ([]MovieRequest, int, error) {
	where := ` FROM movie_requests r JOIN movie_request_shares s ON s.request_id=r.id JOIN users u ON u.id=r.user_id WHERE s.enabled=1 AND u.status=1 AND r.status IN ('pending','processing')`
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*)"+where).Scan(&total); err != nil {
		return nil, 0, err
	}
	limit, offset := contentPage(page, size)
	rows, err := s.db.QueryContext(ctx, `SELECT r.id,r.user_id,COALESCE(NULLIF(u.nickname,''),'同好'),r.title,r.details,r.status,r.created_at,(SELECT COUNT(*) FROM movie_request_supports WHERE request_id=r.id) AS support_count,(SELECT COUNT(*) FROM movie_request_supports WHERE request_id=r.id AND user_id=$1)`+where+" ORDER BY support_count DESC,r.id DESC LIMIT $2 OFFSET $3", user, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := []MovieRequest{}
	for rows.Next() {
		var v MovieRequest
		var supported int
		if err = rows.Scan(&v.ID, &v.UserID, &v.Username, &v.Title, &v.Details, &v.Status, &v.CreatedAt, &v.SupportCount, &supported); err != nil {
			return nil, 0, err
		}
		v.Shared = true
		v.Supported = supported > 0
		items = append(items, v)
	}
	return items, total, rows.Err()
}
