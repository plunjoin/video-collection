package store

import (
	"database/sql"
	"fmt"
	"regexp"
	"strings"
)

// scriptExecutor 抽象 *sql.DB 与 *sql.Tx 的 Exec，便于同一套脚本执行逻辑复用
type scriptExecutor interface {
	Exec(query string, args ...any) (sql.Result, error)
}

// splitStatements 按分号拆分 SQL 脚本。
//
// 只做必要的词法处理：跳过单引号字符串（含连续两个单引号的转义写法）、-- 行注释、/* */ 块注释
// 与 $$ 美元引用，避免把字符串或注释里的分号误判为语句结束。DDL 脚本用不到更复杂的解析。
func splitStatements(script string) []string {
	var (
		out      []string
		cur      strings.Builder
		inSingle bool
		inLine   bool
		inBlock  bool
		inDollar bool
	)
	runes := []rune(script)
	for i := 0; i < len(runes); i++ {
		c := runes[i]
		next := rune(0)
		if i+1 < len(runes) {
			next = runes[i+1]
		}

		switch {
		case inLine:
			cur.WriteRune(c)
			if c == '\n' {
				inLine = false
			}
			continue
		case inBlock:
			cur.WriteRune(c)
			if c == '*' && next == '/' {
				cur.WriteRune(next)
				i++
				inBlock = false
			}
			continue
		case inSingle:
			cur.WriteRune(c)
			if c == '\'' {
				// '' 视为转义的单引号，字符串继续
				if next == '\'' {
					cur.WriteRune(next)
					i++
					continue
				}
				inSingle = false
			}
			continue
		case inDollar:
			cur.WriteRune(c)
			if c == '$' && next == '$' {
				cur.WriteRune(next)
				i++
				inDollar = false
			}
			continue
		}

		switch {
		case c == '-' && next == '-':
			cur.WriteRune(c)
			cur.WriteRune(next)
			i++
			inLine = true
		case c == '/' && next == '*':
			cur.WriteRune(c)
			cur.WriteRune(next)
			i++
			inBlock = true
		case c == '\'':
			cur.WriteRune(c)
			inSingle = true
		case c == '$' && next == '$':
			cur.WriteRune(c)
			cur.WriteRune(next)
			i++
			inDollar = true
		case c == ';':
			if stmt := cleanStatement(cur.String()); stmt != "" {
				out = append(out, stmt)
			}
			cur.Reset()
		default:
			cur.WriteRune(c)
		}
	}
	if stmt := cleanStatement(cur.String()); stmt != "" {
		out = append(out, stmt)
	}
	return out
}

// cleanStatement 去掉语句前后的空白与前导注释（注释对执行无意义，留着只会污染报错信息）
func cleanStatement(raw string) string {
	s := strings.TrimSpace(raw)
	for {
		switch {
		case strings.HasPrefix(s, "--"):
			if idx := strings.IndexByte(s, '\n'); idx >= 0 {
				s = strings.TrimSpace(s[idx+1:])
				continue
			}
			return ""
		case strings.HasPrefix(s, "/*"):
			if idx := strings.Index(s, "*/"); idx >= 0 {
				s = strings.TrimSpace(s[idx+2:])
				continue
			}
			return ""
		}
		return s
	}
}

// complexDDLRe 匹配体内含分号的 DDL（触发器 / 函数 / 存储过程等），这类脚本不能简单按分号拆
var complexDDLRe = regexp.MustCompile(`(?i)create\s+(or\s+replace\s+)?(trigger|function|procedure|rule|event)\b`)

// execScript 逐条执行 DDL 脚本，返回第一条失败语句的原始错误。
//
// 为什么不直接 db.Exec(整个脚本)：PostgreSQL 把多语句简单查询放在同一个隐式事务里，
// 第一条语句失败后后续语句全部返回 "current transaction is aborted"，
// 而 lib/pq 只会返回最后一条错误 —— 真实根因（例如 permission denied for schema public）
// 会被掩盖成 "could not complete operation in a failed transaction"。
func execScript(db scriptExecutor, script string) error {
	// 触发器 / 函数体内部含分号，无法安全拆分，退回整段执行
	if complexDDLRe.MatchString(script) {
		_, err := db.Exec(script)
		return err
	}
	stmts := splitStatements(script)
	if len(stmts) == 0 {
		return nil
	}
	for i, stmt := range stmts {
		if _, err := db.Exec(stmt); err != nil {
			return fmt.Errorf("第 %d/%d 条语句执行失败: %w\n  语句: %s",
				i+1, len(stmts), err, truncateStmt(stmt, 240))
		}
	}
	return nil
}

// truncateStmt 压缩空白并截断长语句，便于日志阅读
func truncateStmt(stmt string, limit int) string {
	compact := strings.Join(strings.Fields(stmt), " ")
	if len(compact) <= limit {
		return compact
	}
	return compact[:limit] + " …"
}
