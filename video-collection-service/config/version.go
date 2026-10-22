package config

import (
	"os"
	"runtime/debug"
	"strings"
	"time"
)

// buildVersion 由构建时通过 ldflags 注入，例如：
//
//	go build -ldflags "-X video-collection-service/config.buildVersion=1.4.0"
var buildVersion = ""

// BuildInfo 返回可读的构建标识，用于在启动日志里确认线上跑的到底是哪份代码。
//
// 排查「明明改了代码、线上行为却没变」这类问题时，没有构建标识基本靠猜：
// 镜像层缓存、忘了重新 build、部署的 tag 不是最新，三种情况日志长得一模一样。
//
// 取值优先级：
//  1. ldflags 注入的版本号
//  2. Go 自动写入的 VCS 信息（仅在含 .git 的目录里构建时存在）
//  3. 二进制自身的修改时间（容器内即镜像构建时间）
func BuildInfo() string {
	parts := make([]string, 0, 3)
	if buildVersion != "" {
		parts = append(parts, "version="+buildVersion)
	}
	if rev, commitTime := vcsBuildInfo(); rev != "" {
		parts = append(parts, "commit="+rev)
		if commitTime != "" {
			parts = append(parts, "commitTime="+commitTime)
		}
	}
	if modTime := binaryModTime(); !modTime.IsZero() {
		parts = append(parts, "buildTime="+modTime.Format("2006-01-02 15:04:05"))
	}
	if len(parts) == 0 {
		return "未知（未注入版本，且无法读取二进制信息）"
	}
	return strings.Join(parts, "  ")
}

// vcsBuildInfo 读取 go build 自动写入的 VCS 信息
func vcsBuildInfo() (revision, commitTime string) {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "", ""
	}
	for _, setting := range info.Settings {
		switch setting.Key {
		case "vcs.revision":
			revision = setting.Value
			if len(revision) > 12 {
				revision = revision[:12]
			}
		case "vcs.time":
			commitTime = setting.Value
		}
	}
	return revision, commitTime
}

// binaryModTime 取当前可执行文件的修改时间，作为构建时间的兜底标识
func binaryModTime() time.Time {
	exePath, err := os.Executable()
	if err != nil {
		return time.Time{}
	}
	fi, err := os.Stat(exePath)
	if err != nil {
		return time.Time{}
	}
	return fi.ModTime()
}
