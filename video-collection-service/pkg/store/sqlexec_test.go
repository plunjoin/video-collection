package store

import "testing"

func TestSplitStatements(t *testing.T) {
	script := `
CREATE TABLE IF NOT EXISTS a (
  id SERIAL PRIMARY KEY,
  note TEXT NOT NULL DEFAULT 'a;b',
  flag INT NOT NULL DEFAULT 0 CHECK(flag IN (0,1))
);
-- 这是注释里的分号; 不应拆开
CREATE INDEX IF NOT EXISTS idx_a ON a(id);
/* 块注释; 也不拆 */
CREATE TABLE b (id INT);
`
	got := splitStatements(script)
	if len(got) != 3 {
		t.Fatalf("期望 3 条语句，实际 %d 条: %#v", len(got), got)
	}
	if got[0][:12] != "CREATE TABLE" {
		t.Fatalf("第一条语句异常: %q", got[0])
	}
	if got[1][:12] != "CREATE INDEX" {
		t.Fatalf("第二条语句异常: %q", got[1])
	}
	if got[2] != "CREATE TABLE b (id INT)" {
		t.Fatalf("第三条语句异常: %q", got[2])
	}
	// 字符串里的分号必须保留
	if !containsSub(got[0], "DEFAULT 'a;b'") {
		t.Fatalf("字符串字面量中的分号被误拆: %q", got[0])
	}
}

func TestSplitStatementsIgnoresTrailingSemicolon(t *testing.T) {
	got := splitStatements("SELECT 1;;; SELECT 2;")
	if len(got) != 2 {
		t.Fatalf("期望 2 条语句，实际 %d: %#v", len(got), got)
	}
	if len(splitStatements("   \n\t ")) != 0 {
		t.Fatalf("空脚本应返回 0 条语句")
	}
}

func containsSub(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}

// 回归：多语句脚本里第一条失败时，必须报出第一条的真实原因，
// 而不是像 PostgreSQL 隐式事务那样只剩最后一条 "current transaction is aborted"。
func TestExecScriptReportsFirstFailure(t *testing.T) {
	s := newTestStore(t)

	script := `
CREATE TABLE IF NOT EXISTS ok_table (id INTEGER PRIMARY KEY);
CREATE INDEX missing_col_idx ON ok_table(no_such_column);
CREATE TABLE IF NOT EXISTS after_failure (id INTEGER PRIMARY KEY);
`
	err := execScript(s.db, script)
	if err == nil {
		t.Fatal("期望报错，实际 nil")
	}
	msg := err.Error()
	if !containsSub(msg, "第 2/3 条") {
		t.Fatalf("应指出失败的是第 2 条语句，实际: %s", msg)
	}
	if !containsSub(msg, "no_such_column") {
		t.Fatalf("应保留原始错误信息，实际: %s", msg)
	}
	if containsSub(msg, "failed transaction") || containsSub(msg, "aborted") {
		t.Fatalf("不应只剩事务中断的泛化错误: %s", msg)
	}
}

// 触发器体内含分号，必须整段执行而不是按分号拆开
func TestExecScriptKeepsTriggerBody(t *testing.T) {
	s := newTestStore(t)
	script := `
CREATE TABLE IF NOT EXISTS trig_src (id INTEGER PRIMARY KEY);
CREATE TRIGGER trig_guard BEFORE INSERT ON trig_src BEGIN SELECT RAISE(ABORT,'blocked'); END;
`
	if err := execScript(s.db, script); err != nil {
		t.Fatalf("触发器脚本应整段执行成功: %v", err)
	}
	if _, err := s.db.Exec("INSERT INTO trig_src(id) VALUES(1)"); err == nil {
		t.Fatal("触发器应生效并阻止插入")
	}
}
