package store

import "os"

// 初始管理员用户名：仅在数据库无任何用户时首次初始化生效。
// 优先级：环境变量 ADMIN_INITIAL_USERNAME > 默认 admin。
// 生产部署可在管理后台「基础配置」中修改（写入 bootstrap SQLite）。
func initialAdminUsername() string {
	if username := os.Getenv("ADMIN_INITIAL_USERNAME"); username != "" {
		return username
	}
	return "admin"
}

// 初始管理员密码：仅在数据库无任何用户时首次初始化生效。
// 优先级：环境变量 ADMIN_INITIAL_PASSWORD > bootstrap 基础配置 > 随机生成回写。
func initialAdminPassword() string {
	if password := os.Getenv("ADMIN_INITIAL_PASSWORD"); password != "" {
		return password
	}
	return "admin123"
}
