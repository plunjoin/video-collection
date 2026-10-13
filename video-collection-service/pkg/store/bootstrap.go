package store

import "os"

func initialAdminPassword() string {
	if password := os.Getenv("ADMIN_INITIAL_PASSWORD"); password != "" {
		return password
	}
	return "admin123"
}
