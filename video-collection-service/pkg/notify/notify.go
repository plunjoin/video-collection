package notify

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"mime"
	"net/http"
	"net/smtp"
	"os"
	"strings"
	"time"
)

// 投递渠道
const (
	ChannelEmail = "email"
	ChannelPhone = "phone"
)

// 验证码用途
const (
	PurposeBind  = "bind"  // 绑定邮箱 / 手机
	PurposeReset = "reset" // 忘记密码找回
)

// ErrNotConfigured 表示该渠道未配置，调用方应提示联系管理员。
var ErrNotConfigured = errors.New("通知渠道未配置")

// Service 验证码投递服务。
// 邮件走标准库 net/smtp（支持 STARTTLS），短信走通用 HTTP 网关；
// 两者都未配置时降级为写日志，便于本地与内网环境自测。
type Service struct {
	host, port, user, pass, from string
	smsWebhook                   string
	siteName                     string
	client                       *http.Client
}

// NewFromEnv 从环境变量构建投递服务：
//
//	SMTP_HOST / SMTP_PORT / SMTP_USER / SMTP_PASS / SMTP_FROM  邮件通道
//	SMS_WEBHOOK_URL                                            短信通道（POST JSON）
//	SITE_NAME                                                  邮件标题里的站点名
func NewFromEnv() *Service {
	return &Service{
		host:       strings.TrimSpace(os.Getenv("SMTP_HOST")),
		port:       firstNonEmpty(os.Getenv("SMTP_PORT"), "587"),
		user:       strings.TrimSpace(os.Getenv("SMTP_USER")),
		pass:       os.Getenv("SMTP_PASS"),
		from:       strings.TrimSpace(os.Getenv("SMTP_FROM")),
		smsWebhook: strings.TrimSpace(os.Getenv("SMS_WEBHOOK_URL")),
		siteName:   firstNonEmpty(os.Getenv("SITE_NAME"), "视频站"),
		client:     &http.Client{Timeout: 8 * time.Second},
	}
}

// DevCodeEnabled 显式开启后，发送验证码接口会把验证码一并返回，
// 仅供无邮件 / 短信通道的联调环境使用。
func DevCodeEnabled() bool {
	return strings.TrimSpace(os.Getenv("ACCOUNT_DEV_CODE")) == "1"
}

func (s *Service) EmailConfigured() bool {
	return s.host != "" && s.from != ""
}

func (s *Service) SMSConfigured() bool {
	return s.smsWebhook != ""
}

func (s *Service) Configured(channel string) bool {
	switch channel {
	case ChannelEmail:
		return s.EmailConfigured()
	case ChannelPhone:
		return s.SMSConfigured()
	}
	return false
}

// Send 投递验证码。未配置渠道时写日志（不返回错误），由调用方决定是否暴露给用户。
func (s *Service) Send(ctx context.Context, channel, target, code, purpose string) error {
	switch channel {
	case ChannelEmail:
		if !s.EmailConfigured() {
			log.Printf("[notify] 邮件通道未配置，验证码仅记录日志: %s -> %s", maskTarget(target), code)
			return ErrNotConfigured
		}
		return s.sendMail(target, code, purpose)
	case ChannelPhone:
		if !s.SMSConfigured() {
			log.Printf("[notify] 短信通道未配置，验证码仅记录日志: %s -> %s", maskTarget(target), code)
			return ErrNotConfigured
		}
		return s.sendSMS(ctx, target, code, purpose)
	}
	return fmt.Errorf("未知投递渠道: %s", channel)
}

func (s *Service) sendMail(to, code, purpose string) error {
	subject := mime.QEncoding.Encode("utf-8", fmt.Sprintf("%s %s验证码", s.siteName, purposeLabel(purpose)))
	body := fmt.Sprintf("%s：\r\n\r\n您正在进行%s操作，验证码为 %s，10 分钟内有效。\r\n如非本人操作，请忽略本邮件并及时修改密码。\r\n\r\n—— %s",
		to, purposeLabel(purpose), code, s.siteName)

	var buf bytes.Buffer
	buf.WriteString("From: " + s.from + "\r\n")
	buf.WriteString("To: " + to + "\r\n")
	buf.WriteString("Subject: " + subject + "\r\n")
	buf.WriteString("MIME-Version: 1.0\r\n")
	buf.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	buf.WriteString("Content-Transfer-Encoding: 8bit\r\n\r\n")
	buf.WriteString(body)

	var auth smtp.Auth
	if s.user != "" {
		auth = smtp.PlainAuth("", s.user, s.pass, s.host)
	}
	addr := s.host + ":" + s.port
	return smtp.SendMail(addr, auth, s.from, []string{to}, buf.Bytes())
}

func (s *Service) sendSMS(ctx context.Context, phone, code, purpose string) error {
	payload, err := json.Marshal(map[string]string{
		"phone":   phone,
		"code":    code,
		"purpose": purpose,
		"text":    fmt.Sprintf("您正在进行%s操作，验证码 %s，10 分钟内有效。", purposeLabel(purpose), code),
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.smsWebhook, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("短信网关返回 %d", resp.StatusCode)
	}
	return nil
}

func purposeLabel(purpose string) string {
	switch purpose {
	case PurposeReset:
		return "找回密码"
	case PurposeBind:
		return "账号绑定"
	}
	return "身份验证"
}

// maskTarget 打日志时脱敏，避免验证码与完整邮箱 / 手机号同时出现在日志里。
func maskTarget(target string) string {
	if at := strings.IndexByte(target, '@'); at > 0 {
		name := target[:at]
		if len(name) > 2 {
			name = name[:2] + "***"
		}
		return name + target[at:]
	}
	if len(target) == 11 {
		return target[:3] + "****" + target[7:]
	}
	return "***"
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v = strings.TrimSpace(v); v != "" {
			return v
		}
	}
	return ""
}
