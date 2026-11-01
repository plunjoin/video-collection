package store

import (
	"context"
	"database/sql"
	"errors"
	"strconv"
	"strings"
	"time"
)

// ErrContactTaken 表示该邮箱 / 手机号已被其他账号绑定。
var ErrContactTaken = errors.New("该联系方式已被其他账号绑定")

// UserContact 账号绑定的联系方式。
// 独立于 User 单独查询：用户列表、鉴权等高频路径不需要这几列。
type UserContact struct {
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
	Phone         string `json:"phone"`
	PhoneVerified bool   `json:"phone_verified"`
}

// VerifyCode 一次性验证码记录。明文不落库，只存 sha256(target + ":" + code)。
type VerifyCode struct {
	Target    string
	Channel   string
	Purpose   string
	CodeHash  string
	ExpiresAt time.Time
}

// 验证码校验允许的最大错误次数，超过后该验证码作废。
const verifyCodeMaxAttempts = 5

// migrateAccount 为旧库补上账号中心所需列与唯一索引。
// users 表由 SQLiteStore / PostgresStore 建，而 verify_codes 在内容子库，
// 两者初始化顺序不保证；只初始化内容子库的单元测试不应因此失败，故先探测表是否存在。
func migrateAccount(db *sql.DB, postgres bool) error {
	var n int
	if err := db.QueryRow("SELECT COUNT(*) FROM users").Scan(&n); err != nil {
		return nil
	}
	columns := []string{"email TEXT NOT NULL DEFAULT ''", "email_verified INTEGER NOT NULL DEFAULT 0",
		"phone TEXT NOT NULL DEFAULT ''", "phone_verified INTEGER NOT NULL DEFAULT 0"}
	for _, col := range columns {
		stmt := "ALTER TABLE users ADD COLUMN " + col
		if postgres {
			stmt = "ALTER TABLE users ADD COLUMN IF NOT EXISTS " + col
			if _, err := db.Exec(stmt); err != nil {
				return err
			}
			continue
		}
		if _, err := db.Exec(stmt); err != nil && !strings.Contains(strings.ToLower(err.Error()), "duplicate column") {
			return err
		}
	}
	// 唯一索引只约束非空值：解绑后留空串，不会互相冲突。
	for _, stmt := range []string{
		"CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email <> ''",
		"CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone <> ''",
	} {
		if _, err := db.Exec(stmt); err != nil {
			return err
		}
	}
	return nil
}

func qmarkPlaceholder(int) string { return "?" }

func dollarPlaceholder(i int) string { return "$" + strconv.Itoa(i) }

// isUniqueViolation 识别两个驱动各自的唯一约束冲突，统一转成 ErrContactTaken。
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "unique constraint") || // SQLite
		strings.Contains(msg, "duplicate key") || // PostgreSQL
		strings.Contains(msg, "unique violation")
}

// constantTimeEqual 定长比较验证码哈希，避免按字节提前返回带来的时序差异。
func constantTimeEqual(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := 0; i < len(a); i++ {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}

// contactColumn 把渠道映射到列名。只走白名单，绝不把请求参数拼进 SQL。
func contactColumn(channel string) (string, bool) {
	switch channel {
	case "email":
		return "email", true
	case "phone":
		return "phone", true
	}
	return "", false
}

// ---------------------------------------------------------------------------
// 通用实现（两个驱动共用，占位符由调用方提供）
// ---------------------------------------------------------------------------

func queryContact(ctx context.Context, db *sql.DB, id int, ph func(int) string) (*UserContact, error) {
	c := &UserContact{}
	var emailVerified, phoneVerified int
	err := db.QueryRowContext(ctx, `
		SELECT COALESCE(email,''), COALESCE(email_verified,0), COALESCE(phone,''), COALESCE(phone_verified,0)
		FROM users WHERE id = `+ph(1), id).
		Scan(&c.Email, &emailVerified, &c.Phone, &phoneVerified)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	c.EmailVerified = emailVerified == 1
	c.PhoneVerified = phoneVerified == 1
	return c, nil
}

func queryUserByContact(ctx context.Context, db *sql.DB, channel, value string, ph func(int) string) (*User, error) {
	col, ok := contactColumn(channel)
	if !ok {
		return nil, nil
	}
	u := &User{}
	row := db.QueryRowContext(ctx, `
		SELECT id, username, password_hash, nickname, avatar, bio, role, status, created_at, updated_at
		FROM users WHERE `+col+` = `+ph(1)+` AND `+col+` <> '' LIMIT 1`, value)
	err := row.Scan(&u.ID, &u.Username, &u.PasswordHash, &u.Nickname, &u.Avatar, &u.Bio, &u.Role, &u.Status, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return u, nil
}

func bindContact(ctx context.Context, db *sql.DB, id int, channel, value string, ph func(int) string) error {
	col, ok := contactColumn(channel)
	if !ok {
		return ErrInvalidOperation
	}
	// 先查占用，给出明确提示（唯一索引是最后一道防线）。
	var owner int
	err := db.QueryRowContext(ctx, "SELECT id FROM users WHERE "+col+" = "+ph(1)+" AND id <> "+ph(2)+" LIMIT 1", value, id).Scan(&owner)
	if err == nil {
		return ErrContactTaken
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	_, err = db.ExecContext(ctx,
		"UPDATE users SET "+col+" = "+ph(1)+", "+col+"_verified = 1, updated_at = "+ph(2)+" WHERE id = "+ph(3),
		value, time.Now(), id)
	if err != nil && isUniqueViolation(err) {
		return ErrContactTaken
	}
	return err
}

func unbindContact(ctx context.Context, db *sql.DB, id int, channel string, ph func(int) string) error {
	col, ok := contactColumn(channel)
	if !ok {
		return ErrInvalidOperation
	}
	_, err := db.ExecContext(ctx,
		"UPDATE users SET "+col+" = '', "+col+"_verified = 0, updated_at = "+ph(1)+" WHERE id = "+ph(2),
		time.Now(), id)
	return err
}

// anonymizeUser 注销账号：保留行与历史内容（作者显示为「已注销用户」），
// 清空可识别信息并置 status=2，同时把密码换成永不可用的占位串。
func anonymizeUser(ctx context.Context, db *sql.DB, id int, ph func(int) string) error {
	_, err := db.ExecContext(ctx, `
		UPDATE users SET username = `+ph(1)+`, nickname = `+ph(2)+`, password_hash = `+ph(3)+`,
			avatar = '', bio = '', email = '', email_verified = 0, phone = '', phone_verified = 0,
			status = 2, updated_at = `+ph(4)+`
		WHERE id = `+ph(5),
		"deleted_"+strconv.Itoa(id), "已注销用户", "!deleted", time.Now(), id)
	return err
}

func insertVerifyCode(ctx context.Context, db *sql.DB, vc *VerifyCode, ph func(int) string) error {
	_, err := db.ExecContext(ctx, `
		INSERT INTO verify_codes (target, channel, purpose, code_hash, attempts, consumed, expires_at, created_at)
		VALUES (`+ph(1)+`, `+ph(2)+`, `+ph(3)+`, `+ph(4)+`, 0, 0, `+ph(5)+`, `+ph(6)+`)
	`, vc.Target, vc.Channel, vc.Purpose, vc.CodeHash, vc.ExpiresAt, time.Now())
	return err
}

// consumeVerifyCode 校验并消费最近一条未使用的验证码。
// 无论成功与否都会累加尝试次数，超过上限或已过期时直接作废，防止爆破与重放。
func consumeVerifyCode(ctx context.Context, db *sql.DB, target, channel, purpose, codeHash string, ph func(int) string) (bool, error) {
	var (
		id       int
		hash     string
		attempts int
		expires  time.Time
	)
	err := db.QueryRowContext(ctx, `
		SELECT id, code_hash, attempts, expires_at FROM verify_codes
		WHERE target = `+ph(1)+` AND channel = `+ph(2)+` AND purpose = `+ph(3)+` AND consumed = 0
		ORDER BY id DESC LIMIT 1`, target, channel, purpose).Scan(&id, &hash, &attempts, &expires)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}

	expired := time.Now().After(expires)
	if expired || attempts >= verifyCodeMaxAttempts {
		_, _ = db.ExecContext(ctx, "UPDATE verify_codes SET consumed = 1 WHERE id = "+ph(1), id)
		return false, nil
	}

	// 先占位消费，避免并发请求用同一验证码通过多次校验。
	res, err := db.ExecContext(ctx, "UPDATE verify_codes SET consumed = 1 WHERE id = "+ph(1)+" AND consumed = 0", id)
	if err != nil {
		return false, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return false, nil
	}
	if !constantTimeEqual(hash, codeHash) {
		_, _ = db.ExecContext(ctx, "UPDATE verify_codes SET consumed = 0, attempts = attempts + 1 WHERE id = "+ph(1), id)
		return false, nil
	}
	return true, nil
}

// ---------------------------------------------------------------------------
// SQLite
// ---------------------------------------------------------------------------

func (s *SQLiteStore) GetUserContact(ctx context.Context, id int) (*UserContact, error) {
	return queryContact(ctx, s.db, id, qmarkPlaceholder)
}

func (s *SQLiteStore) GetUserByContact(ctx context.Context, channel, value string) (*User, error) {
	return queryUserByContact(ctx, s.db, channel, value, qmarkPlaceholder)
}

func (s *SQLiteStore) BindContact(ctx context.Context, id int, channel, value string) error {
	return bindContact(ctx, s.db, id, channel, value, qmarkPlaceholder)
}

func (s *SQLiteStore) UnbindContact(ctx context.Context, id int, channel string) error {
	return unbindContact(ctx, s.db, id, channel, qmarkPlaceholder)
}

func (s *SQLiteStore) UpdateAvatar(ctx context.Context, id int, avatar string) error {
	_, err := s.db.ExecContext(ctx, "UPDATE users SET avatar = ?, updated_at = ? WHERE id = ?", avatar, time.Now(), id)
	return err
}

func (s *SQLiteStore) AnonymizeUser(ctx context.Context, id int) error {
	return anonymizeUser(ctx, s.db, id, qmarkPlaceholder)
}

func (s *SQLiteStore) CreateVerifyCode(ctx context.Context, vc *VerifyCode) error {
	return insertVerifyCode(ctx, s.db, vc, qmarkPlaceholder)
}

func (s *SQLiteStore) ConsumeVerifyCode(ctx context.Context, target, channel, purpose, codeHash string) (bool, error) {
	return consumeVerifyCode(ctx, s.db, target, channel, purpose, codeHash, qmarkPlaceholder)
}

// ---------------------------------------------------------------------------
// PostgreSQL
// ---------------------------------------------------------------------------

func (s *PostgresStore) GetUserContact(ctx context.Context, id int) (*UserContact, error) {
	return queryContact(ctx, s.db, id, dollarPlaceholder)
}

func (s *PostgresStore) GetUserByContact(ctx context.Context, channel, value string) (*User, error) {
	return queryUserByContact(ctx, s.db, channel, value, dollarPlaceholder)
}

func (s *PostgresStore) BindContact(ctx context.Context, id int, channel, value string) error {
	return bindContact(ctx, s.db, id, channel, value, dollarPlaceholder)
}

func (s *PostgresStore) UnbindContact(ctx context.Context, id int, channel string) error {
	return unbindContact(ctx, s.db, id, channel, dollarPlaceholder)
}

func (s *PostgresStore) UpdateAvatar(ctx context.Context, id int, avatar string) error {
	_, err := s.db.ExecContext(ctx, "UPDATE users SET avatar = $1, updated_at = NOW() WHERE id = $2", avatar, id)
	return err
}

func (s *PostgresStore) AnonymizeUser(ctx context.Context, id int) error {
	return anonymizeUser(ctx, s.db, id, dollarPlaceholder)
}

func (s *PostgresStore) CreateVerifyCode(ctx context.Context, vc *VerifyCode) error {
	return insertVerifyCode(ctx, s.db, vc, dollarPlaceholder)
}

func (s *PostgresStore) ConsumeVerifyCode(ctx context.Context, target, channel, purpose, codeHash string) (bool, error) {
	return consumeVerifyCode(ctx, s.db, target, channel, purpose, codeHash, dollarPlaceholder)
}
