package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

var ErrInsufficientPoints = errors.New("积分不足")

type GrowthRules struct {
	Active      int `json:"active"`
	Checkin     int `json:"checkin"`
	StreakStep  int `json:"streak_step"`
	StreakCap   int `json:"streak_cap"`
	RequestCost int `json:"request_cost"`
}
type Cosmetic struct {
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Kind     string `json:"kind"`
	Value    string `json:"value"`
	Price    int    `json:"price"`
	Active   bool   `json:"active"`
	Owned    bool   `json:"owned"`
	Equipped bool   `json:"equipped"`
}
type Decorations struct {
	Avatar        string `json:"avatar"`
	Frame         string `json:"frame"`
	Badge         string `json:"badge"`
	NicknameColor string `json:"nickname_color"`
}
type LedgerEntry struct {
	ID        int    `json:"id"`
	Amount    int    `json:"amount"`
	Balance   int    `json:"balance"`
	Reason    string `json:"reason"`
	CreatedAt string `json:"created_at"`
}
type MovieRequest struct {
	ID           int    `json:"id"`
	UserID       int    `json:"user_id"`
	Username     string `json:"username"`
	Title        string `json:"title"`
	Details      string `json:"details"`
	Cost         int    `json:"cost"`
	Status       string `json:"status"`
	Reply        string `json:"reply"`
	CreatedAt    string `json:"created_at"`
	UpdatedAt    string `json:"updated_at"`
	Shared       bool   `json:"shared"`
	SupportCount int    `json:"support_count"`
	Supported    bool   `json:"supported"`
}
type DayActivity struct {
	Day      string `json:"day"`
	DAU      int    `json:"dau"`
	Checkins int    `json:"checkins"`
	Earned   int    `json:"earned"`
	Spent    int    `json:"spent"`
}
type GrowthStore interface {
	JourneyStore
	RecordActivity(context.Context, int, time.Time) error
	Checkin(context.Context, int, time.Time) (int, error)
	Wallet(context.Context, int) (map[string]any, error)
	PointsBalance(context.Context, int) (int, error)
	GrowthRules(context.Context) (GrowthRules, error)
	SaveGrowthRules(context.Context, GrowthRules) error
	ListCosmetics(context.Context, int, bool) ([]Cosmetic, error)
	SaveCosmetic(context.Context, *Cosmetic) error
	Redeem(context.Context, int, int) error
	Equip(context.Context, int, int, string) error
	Decorations(context.Context, int) (Decorations, error)
	CreateMovieRequest(context.Context, *MovieRequest) error
	ListMovieRequests(context.Context, int, int, int) ([]MovieRequest, int, error)
	ResolveMovieRequest(context.Context, int, int, string, string) error
	GrowthStats(context.Context) ([]DayActivity, error)
}

func (s *SQLContentStore) PointsBalance(ctx context.Context, user int) (int, error) {
	var balance int
	err := s.db.QueryRowContext(ctx, "SELECT balance FROM point_wallets WHERE user_id=$1", user).Scan(&balance)
	if errors.Is(err, sql.ErrNoRows) {
		err = nil
	}
	return balance, err
}

func migrateGrowth(tx *sql.Tx, id string) error {
	_, err := tx.Exec(fmt.Sprintf(`
	CREATE TABLE IF NOT EXISTS admin_operations(id %s,actor_id INTEGER NOT NULL,method TEXT NOT NULL,path TEXT NOT NULL,status INTEGER NOT NULL,created_at TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS governance_guard(id INTEGER PRIMARY KEY);
 INSERT INTO governance_guard(id) VALUES(1) ON CONFLICT(id) DO NOTHING;
 CREATE TABLE IF NOT EXISTS content_reviews(id %s,kind TEXT NOT NULL,target_id INTEGER NOT NULL DEFAULT 0,submitter_id INTEGER NOT NULL,payload TEXT NOT NULL,baseline TEXT NOT NULL DEFAULT '',status TEXT NOT NULL CHECK(status IN ('pending','approved','rejected')),reviewer_id INTEGER NOT NULL DEFAULT 0,note TEXT NOT NULL DEFAULT '',created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
 CREATE INDEX IF NOT EXISTS idx_reviews_status ON content_reviews(status,submitter_id,id);
 CREATE TABLE IF NOT EXISTS point_wallets(user_id INTEGER PRIMARY KEY,balance INTEGER NOT NULL DEFAULT 0 CHECK(balance>=0));
 CREATE TABLE IF NOT EXISTS point_ledger(id %s,user_id INTEGER NOT NULL,amount INTEGER NOT NULL,balance INTEGER NOT NULL,reason TEXT NOT NULL,event_key TEXT NOT NULL,day TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE(user_id,event_key));
 CREATE INDEX IF NOT EXISTS idx_ledger_user ON point_ledger(user_id,id);
 CREATE INDEX IF NOT EXISTS idx_ledger_day ON point_ledger(day);
 CREATE TABLE IF NOT EXISTS daily_activity(user_id INTEGER NOT NULL,day TEXT NOT NULL,PRIMARY KEY(user_id,day));
 CREATE TABLE IF NOT EXISTS daily_checkins(user_id INTEGER NOT NULL,day TEXT NOT NULL,streak INTEGER NOT NULL,PRIMARY KEY(user_id,day));
 CREATE TABLE IF NOT EXISTS growth_settings(id INTEGER PRIMARY KEY,rules TEXT NOT NULL);
 INSERT INTO growth_settings(id,rules) VALUES(1,'{"active":5,"checkin":10,"streak_step":2,"streak_cap":30,"request_cost":20}') ON CONFLICT(id) DO NOTHING;
 CREATE TABLE IF NOT EXISTS cosmetic_catalog(id %s,name TEXT NOT NULL,kind TEXT NOT NULL,value TEXT NOT NULL,price INTEGER NOT NULL CHECK(price>=0),active INTEGER NOT NULL DEFAULT 1 CHECK(active IN(0,1)));
 CREATE TABLE IF NOT EXISTS cosmetic_inventory(user_id INTEGER NOT NULL,item_id INTEGER NOT NULL REFERENCES cosmetic_catalog(id),created_at TEXT NOT NULL,PRIMARY KEY(user_id,item_id));
 CREATE TABLE IF NOT EXISTS cosmetic_equipment(user_id INTEGER NOT NULL,slot TEXT NOT NULL,item_id INTEGER NOT NULL REFERENCES cosmetic_catalog(id),PRIMARY KEY(user_id,slot));
 CREATE TABLE IF NOT EXISTS movie_requests(id %s,user_id INTEGER NOT NULL,title TEXT NOT NULL,details TEXT NOT NULL,cost INTEGER NOT NULL CHECK(cost>=0),status TEXT NOT NULL CHECK(status IN ('pending','processing','fulfilled','rejected')),reply TEXT NOT NULL DEFAULT '',created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
 CREATE INDEX IF NOT EXISTS idx_requests_user ON movie_requests(user_id,id);
 `, id, id, id, id, id))
	if err != nil {
		return err
	}
	if err = migrateJourney(tx); err != nil {
		return err
	}
	// Only the original bootstrap account is promoted on an existing installation.
	marker, err := tx.Exec("INSERT INTO content_migrations(name) VALUES('governance_growth_v1') ON CONFLICT(name) DO NOTHING")
	if err != nil {
		return err
	}
	n, _ := marker.RowsAffected()
	if n == 0 {
		return nil
	}
	if _, err = tx.Exec("UPDATE users SET role='super_admin' WHERE username='admin' AND role='admin' AND NOT EXISTS(SELECT 1 FROM users WHERE role='super_admin')"); err != nil {
		return err
	}
	seeds := []Cosmetic{{Name: "星际旅人", Kind: "avatar", Value: "/api/cosmetics/orbit.svg", Price: 30}, {Name: "流光星球", Kind: "animated_avatar", Value: "/api/cosmetics/pulse.svg", Price: 80}, {Name: "晨曦光环", Kind: "frame", Value: "#f59e0b", Price: 40}, {Name: "同好先锋", Kind: "badge", Value: "同好先锋", Price: 50}, {Name: "紫罗兰昵称", Kind: "nickname_color", Value: "#a78bfa", Price: 30}, {Name: "碧海昵称", Kind: "nickname_color", Value: "#22d3ee", Price: 30}}
	for _, c := range seeds {
		if _, err = tx.Exec("INSERT INTO cosmetic_catalog(name,kind,value,price) VALUES($1,$2,$3,$4)", c.Name, c.Kind, c.Value, c.Price); err != nil {
			return err
		}
	}
	return nil
}

var businessZone = time.FixedZone("Asia/Shanghai", 8*60*60)

func businessDay(t time.Time) string { return t.In(businessZone).Format("2006-01-02") }
func lockWallet(ctx context.Context, tx *sql.Tx, user int) error {
	if _, err := tx.ExecContext(ctx, "INSERT INTO point_wallets(user_id) VALUES($1) ON CONFLICT(user_id) DO NOTHING", user); err != nil {
		return err
	}
	_, err := tx.ExecContext(ctx, "UPDATE point_wallets SET balance=balance WHERE user_id=$1", user)
	return err
}
func addPoints(ctx context.Context, tx *sql.Tx, user, amount int, reason, key string, now time.Time) error {
	var exists int
	if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM point_ledger WHERE user_id=$1 AND event_key=$2", user, key).Scan(&exists); err != nil {
		return err
	}
	if exists > 0 {
		return nil
	}
	var balance int
	err := tx.QueryRowContext(ctx, "UPDATE point_wallets SET balance=balance+$1 WHERE user_id=$2 AND balance+$1>=0 RETURNING balance", amount, user).Scan(&balance)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInsufficientPoints
	}
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, "INSERT INTO point_ledger(user_id,amount,balance,reason,event_key,day,created_at) VALUES($1,$2,$3,$4,$5,$6,$7)", user, amount, balance, reason, key, businessDay(now), now.UTC().Format(time.RFC3339Nano))
	return err
}
func rulesTx(ctx context.Context, tx *sql.Tx) (GrowthRules, error) {
	var raw string
	var r GrowthRules
	err := tx.QueryRowContext(ctx, "SELECT rules FROM growth_settings WHERE id=1").Scan(&raw)
	if err == nil {
		err = json.Unmarshal([]byte(raw), &r)
	}
	return r, err
}
func (s *SQLContentStore) GrowthRules(ctx context.Context) (GrowthRules, error) {
	var raw string
	var r GrowthRules
	err := s.db.QueryRowContext(ctx, "SELECT rules FROM growth_settings WHERE id=1").Scan(&raw)
	if err == nil {
		err = json.Unmarshal([]byte(raw), &r)
	}
	return r, err
}
func (s *SQLContentStore) SaveGrowthRules(ctx context.Context, r GrowthRules) error {
	if r.Active < 0 || r.Active > 100 || r.Checkin < 0 || r.Checkin > 100 || r.StreakStep < 0 || r.StreakStep > 20 || r.StreakCap < r.Checkin || r.StreakCap > 500 || r.RequestCost < 1 || r.RequestCost > 10000 {
		return ErrInvalidOperation
	}
	raw, _ := json.Marshal(r)
	_, err := s.db.ExecContext(ctx, "UPDATE growth_settings SET rules=$1 WHERE id=1", string(raw))
	return err
}
func (s *SQLContentStore) RecordActivity(ctx context.Context, user int, now time.Time) error {
	// Fast read avoids a write transaction on every authenticated request.
	var exists int
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM daily_activity WHERE user_id=$1 AND day=$2", user, businessDay(now)).Scan(&exists); err != nil {
		return err
	}
	if exists > 0 {
		return nil
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = lockWallet(ctx, tx, user); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO daily_activity(user_id,day) VALUES($1,$2) ON CONFLICT(user_id,day) DO NOTHING", user, businessDay(now)); err != nil {
		return err
	}
	rules, err := rulesTx(ctx, tx)
	if err != nil {
		return err
	}
	if err = addPoints(ctx, tx, user, rules.Active, "每日活跃", "active:"+businessDay(now), now); err != nil {
		return err
	}
	return tx.Commit()
}
func (s *SQLContentStore) Checkin(ctx context.Context, user int, now time.Time) (int, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	if err = lockWallet(ctx, tx, user); err != nil {
		return 0, err
	}
	var previous string
	var streak int
	err = tx.QueryRowContext(ctx, "SELECT day,streak FROM daily_checkins WHERE user_id=$1 ORDER BY day DESC LIMIT 1", user).Scan(&previous, &streak)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	day := businessDay(now)
	if previous == day {
		return 0, tx.Commit()
	}
	if previous == businessDay(now.AddDate(0, 0, -1)) {
		streak++
	} else {
		streak = 1
	}
	r, err := rulesTx(ctx, tx)
	if err != nil {
		return 0, err
	}
	amount := r.Checkin + (streak-1)*r.StreakStep
	if amount > r.StreakCap {
		amount = r.StreakCap
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO daily_checkins(user_id,day,streak) VALUES($1,$2,$3)", user, day, streak); err != nil {
		return 0, err
	}
	if err = addPoints(ctx, tx, user, amount, "每日签到", "checkin:"+day, now); err != nil {
		return 0, err
	}
	return amount, tx.Commit()
}
func (s *SQLContentStore) Wallet(ctx context.Context, user int) (map[string]any, error) {
	balance := 0
	err := s.db.QueryRowContext(ctx, "SELECT balance FROM point_wallets WHERE user_id=$1", user).Scan(&balance)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}
	var day string
	var streak int
	err = s.db.QueryRowContext(ctx, "SELECT day,streak FROM daily_checkins WHERE user_id=$1 ORDER BY day DESC LIMIT 1", user).Scan(&day, &streak)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}
	now := time.Now()
	if day != businessDay(now) && day != businessDay(now.AddDate(0, 0, -1)) {
		streak = 0
	}
	rows, err := s.db.QueryContext(ctx, "SELECT id,amount,balance,reason,created_at FROM point_ledger WHERE user_id=$1 ORDER BY id DESC LIMIT 100", user)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ledger := []LedgerEntry{}
	for rows.Next() {
		var v LedgerEntry
		if err = rows.Scan(&v.ID, &v.Amount, &v.Balance, &v.Reason, &v.CreatedAt); err != nil {
			return nil, err
		}
		ledger = append(ledger, v)
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	return map[string]any{"balance": balance, "checked_in": day == businessDay(now), "streak": streak, "day": businessDay(now), "ledger": ledger}, nil
}
func (s *SQLContentStore) ListCosmetics(ctx context.Context, user int, admin bool) ([]Cosmetic, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT c.id,c.name,c.kind,c.value,c.price,c.active,(SELECT COUNT(*) FROM cosmetic_inventory i WHERE i.user_id=$1 AND i.item_id=c.id),(SELECT COUNT(*) FROM cosmetic_equipment e WHERE e.user_id=$1 AND e.item_id=c.id) FROM cosmetic_catalog c WHERE ($2=1 OR c.active=1 OR EXISTS(SELECT 1 FROM cosmetic_inventory i WHERE i.user_id=$1 AND i.item_id=c.id)) ORDER BY c.id`, user, boolInt(admin))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Cosmetic{}
	for rows.Next() {
		var c Cosmetic
		var active, owned, equipped int
		if err = rows.Scan(&c.ID, &c.Name, &c.Kind, &c.Value, &c.Price, &active, &owned, &equipped); err != nil {
			return nil, err
		}
		c.Active = active == 1
		c.Owned = owned > 0
		c.Equipped = equipped > 0
		items = append(items, c)
	}
	return items, rows.Err()
}

var hexColor = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)

func (s *SQLContentStore) SaveCosmetic(ctx context.Context, c *Cosmetic) error {
	c.Name = strings.TrimSpace(c.Name)
	if c.ID < 0 || c.Name == "" || utf8.RuneCountInString(c.Name) > 40 || c.Price < 0 || c.Price > 100000 || len(c.Value) > 2048 {
		return ErrInvalidOperation
	}
	switch c.Kind {
	case "avatar", "animated_avatar":
		u, e := url.Parse(c.Value)
		if e != nil || !(strings.HasPrefix(c.Value, "/api/cosmetics/") || (u.Scheme == "https" && u.Host != "" && u.User == nil)) {
			return ErrInvalidOperation
		}
	case "frame", "nickname_color":
		if !hexColor.MatchString(c.Value) {
			return ErrInvalidOperation
		}
	case "badge":
		if strings.TrimSpace(c.Value) == "" || utf8.RuneCountInString(c.Value) > 12 {
			return ErrInvalidOperation
		}
	default:
		return ErrInvalidOperation
	}
	if c.ID == 0 {
		return s.db.QueryRowContext(ctx, "INSERT INTO cosmetic_catalog(name,kind,value,price,active) VALUES($1,$2,$3,$4,$5) RETURNING id", c.Name, c.Kind, c.Value, c.Price, boolInt(c.Active)).Scan(&c.ID)
	}
	res, err := s.db.ExecContext(ctx, "UPDATE cosmetic_catalog SET name=$1,value=$2,price=$3,active=$4 WHERE id=$5 AND kind=$6", c.Name, c.Value, c.Price, boolInt(c.Active), c.ID, c.Kind)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrConflict
	}
	return nil
}
func (s *SQLContentStore) Redeem(ctx context.Context, user, item int) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = lockWallet(ctx, tx, user); err != nil {
		return err
	}
	var price int
	var name string
	if err = tx.QueryRowContext(ctx, "UPDATE cosmetic_catalog SET id=id WHERE id=$1 AND active=1 RETURNING price,name", item).Scan(&price, &name); err != nil {
		return ErrContentNotFound
	}
	var owned int
	if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM cosmetic_inventory WHERE user_id=$1 AND item_id=$2", user, item).Scan(&owned); err != nil {
		return err
	}
	if owned > 0 {
		return tx.Commit()
	}
	now := time.Now()
	if err = addPoints(ctx, tx, user, -price, "兑换："+name, fmt.Sprint("redeem:", item), now); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO cosmetic_inventory(user_id,item_id,created_at) VALUES($1,$2,$3)", user, item, now.UTC().Format(time.RFC3339Nano)); err != nil {
		return err
	}
	if err = insertNotification(ctx, tx, &Notification{UserID: user, Type: "system", Title: "装扮兑换成功", Content: name, TargetType: "points"}); err != nil {
		return err
	}
	return tx.Commit()
}
func cosmeticSlot(kind string) string {
	if kind == "animated_avatar" {
		return "avatar"
	}
	return kind
}
func (s *SQLContentStore) Equip(ctx context.Context, user, item int, slot string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = lockWallet(ctx, tx, user); err != nil {
		return err
	}
	if item == 0 {
		if slot != "avatar" && slot != "frame" && slot != "badge" && slot != "nickname_color" {
			return ErrInvalidOperation
		}
		_, err = tx.ExecContext(ctx, "DELETE FROM cosmetic_equipment WHERE user_id=$1 AND slot=$2", user, slot)
	} else {
		var kind string
		if err = tx.QueryRowContext(ctx, "SELECT c.kind FROM cosmetic_catalog c JOIN cosmetic_inventory i ON i.item_id=c.id WHERE i.user_id=$1 AND c.id=$2", user, item).Scan(&kind); err != nil {
			return ErrContentForbidden
		}
		slot = cosmeticSlot(kind)
		_, err = tx.ExecContext(ctx, "INSERT INTO cosmetic_equipment(user_id,slot,item_id) VALUES($1,$2,$3) ON CONFLICT(user_id,slot) DO UPDATE SET item_id=excluded.item_id", user, slot, item)
	}
	if err != nil {
		return err
	}
	return tx.Commit()
}
func (s *SQLContentStore) Decorations(ctx context.Context, user int) (Decorations, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT e.slot,c.value FROM cosmetic_equipment e JOIN cosmetic_catalog c ON c.id=e.item_id WHERE e.user_id=$1", user)
	if err != nil {
		return Decorations{}, err
	}
	defer rows.Close()
	d := Decorations{}
	for rows.Next() {
		var slot, value string
		if err = rows.Scan(&slot, &value); err != nil {
			return d, err
		}
		switch slot {
		case "avatar":
			d.Avatar = value
		case "frame":
			d.Frame = value
		case "badge":
			d.Badge = value
		case "nickname_color":
			d.NicknameColor = value
		}
	}
	return d, rows.Err()
}
func (s *SQLContentStore) CreateMovieRequest(ctx context.Context, v *MovieRequest) error {
	v.Title = strings.TrimSpace(v.Title)
	v.Details = strings.TrimSpace(v.Details)
	if v.UserID < 1 || v.Title == "" || utf8.RuneCountInString(v.Title) > 200 || utf8.RuneCountInString(v.Details) > 2000 {
		return ErrInvalidOperation
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = lockWallet(ctx, tx, v.UserID); err != nil {
		return err
	}
	var count int
	if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM movie_requests WHERE user_id=$1 AND (status='pending' OR status='processing')", v.UserID).Scan(&count); err != nil {
		return err
	}
	if count >= 5 {
		return fmt.Errorf("最多同时提交5个未完成求片: %w", ErrInvalidOperation)
	}
	if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM movie_requests WHERE user_id=$1 AND LOWER(title)=LOWER($2) AND status IN ('pending','processing')", v.UserID, v.Title).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return ErrConflict
	}
	r, err := rulesTx(ctx, tx)
	if err != nil {
		return err
	}
	v.Cost = r.RequestCost
	v.Status = "pending"
	now := time.Now()
	v.CreatedAt = now.UTC().Format(time.RFC3339Nano)
	v.UpdatedAt = v.CreatedAt
	if err = tx.QueryRowContext(ctx, "INSERT INTO movie_requests(user_id,title,details,cost,status,created_at,updated_at) VALUES($1,$2,$3,$4,'pending',$5,$5) RETURNING id", v.UserID, v.Title, v.Details, v.Cost, v.CreatedAt).Scan(&v.ID); err != nil {
		return err
	}
	if err = addPoints(ctx, tx, v.UserID, -v.Cost, "积分求片", fmt.Sprint("request:", v.ID), now); err != nil {
		return err
	}
	if err = notifyAdmins(ctx, tx, v.UserID, "新的积分求片", v.Title, "movie_request", v.ID); err != nil {
		return err
	}
	return tx.Commit()
}
func (s *SQLContentStore) ListMovieRequests(ctx context.Context, user, page, size int) ([]MovieRequest, int, error) {
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM movie_requests WHERE ($1=0 OR user_id=$1)", user).Scan(&total); err != nil {
		return nil, 0, err
	}
	limit, offset := contentPage(page, size)
	rows, err := s.db.QueryContext(ctx, `SELECT r.id,r.user_id,COALESCE(u.username,''),r.title,r.details,r.cost,r.status,r.reply,r.created_at,r.updated_at,COALESCE((SELECT enabled FROM movie_request_shares WHERE request_id=r.id),0),(SELECT COUNT(*) FROM movie_request_supports WHERE request_id=r.id) FROM movie_requests r LEFT JOIN users u ON u.id=r.user_id WHERE ($1=0 OR r.user_id=$1) ORDER BY r.id DESC LIMIT $2 OFFSET $3`, user, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := []MovieRequest{}
	for rows.Next() {
		var v MovieRequest
		var shared int
		if err = rows.Scan(&v.ID, &v.UserID, &v.Username, &v.Title, &v.Details, &v.Cost, &v.Status, &v.Reply, &v.CreatedAt, &v.UpdatedAt, &shared, &v.SupportCount); err != nil {
			return nil, 0, err
		}
		v.Shared = shared == 1
		items = append(items, v)
	}
	return items, total, rows.Err()
}
func (s *SQLContentStore) ResolveMovieRequest(ctx context.Context, id, actor int, status, reply string) error {
	if status != "processing" && status != "fulfilled" && status != "rejected" {
		return ErrInvalidOperation
	}
	if strings.TrimSpace(reply) == "" || utf8.RuneCountInString(reply) > 2000 {
		return ErrInvalidOperation
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var user int
	if err = tx.QueryRowContext(ctx, "SELECT user_id FROM movie_requests WHERE id=$1", id).Scan(&user); err != nil {
		return ErrContentNotFound
	}
	if err = lockWallet(ctx, tx, user); err != nil {
		return err
	}
	var cost int
	var old string
	if err = tx.QueryRowContext(ctx, "UPDATE movie_requests SET id=id WHERE id=$1 RETURNING cost,status", id).Scan(&cost, &old); err != nil {
		return err
	}
	if old == "fulfilled" || old == "rejected" || old == status {
		return ErrConflict
	}
	if status == "rejected" {
		if err = addPoints(ctx, tx, user, cost, "求片未采纳退款", fmt.Sprint("refund:", id), time.Now()); err != nil {
			return err
		}
	}
	if _, err = tx.ExecContext(ctx, "UPDATE movie_requests SET status=$1,reply=$2,updated_at=$3 WHERE id=$4", status, reply, time.Now().UTC().Format(time.RFC3339Nano), id); err != nil {
		return err
	}
	statusLabel := map[string]string{"processing": "寻找中", "fulfilled": "已完成", "rejected": "未采纳，积分已退还"}[status]
	if err = insertNotification(ctx, tx, &Notification{UserID: user, ActorID: actor, Type: "system", Title: "求片状态：" + statusLabel, Content: reply, TargetType: "movie_request", TargetID: id}); err != nil {
		return err
	}
	return tx.Commit()
}
func (s *SQLContentStore) GrowthStats(ctx context.Context) ([]DayActivity, error) {
	start := businessDay(time.Now().AddDate(0, 0, -29))
	rows, err := s.db.QueryContext(ctx, `SELECT day,COUNT(*),(SELECT COUNT(*) FROM daily_checkins c WHERE c.day=a.day),COALESCE((SELECT SUM(amount) FROM point_ledger l WHERE l.day=a.day AND amount>0),0),COALESCE((SELECT -SUM(amount) FROM point_ledger l WHERE l.day=a.day AND amount<0),0) FROM daily_activity a WHERE day >= $1 GROUP BY day ORDER BY day`, start)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []DayActivity{}
	for rows.Next() {
		var d DayActivity
		if err = rows.Scan(&d.Day, &d.DAU, &d.Checkins, &d.Earned, &d.Spent); err != nil {
			return nil, err
		}
		items = append(items, d)
	}
	return items, rows.Err()
}
