// Package notify 负责把验证码投递到邮箱或手机。
//
// 通道参数（SMTP / 短信网关）来自 integration 配置，可在后台修改后即时生效；
// 邮件标题与正文、短信文案都支持模板占位符。
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
	"strconv"
	"strings"
	"time"

	"video-collection-service/pkg/integration"
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

// Service 一次投递所需的通道参数快照。
type Service struct {
	mail    integration.Mail
	sms     integration.SMS
	site    string
	devMode bool
	client  *http.Client
}

// FromConfig 用配置构建投递服务。devMode 为真时允许接口回传验证码（仅联调）。
func FromConfig(cfg integration.Config, devMode bool) *Service {
	site := strings.TrimSpace(cfg.Mail.FromName)
	if site == "" {
		site = strings.TrimSpace(integration.Env("SITE_NAME"))
	}
	if site == "" {
		site = "视频站"
	}
	return &Service{
		mail:    cfg.Mail,
		sms:     cfg.SMS,
		site:    site,
		devMode: devMode,
		client:  &http.Client{Timeout: 8 * time.Second},
	}
}

// DevMode 是否开启验证码回传。
func (s *Service) DevMode() bool { return s.devMode }

// DevCodeEnabled 显式开启后，发送验证码接口会把验证码一并返回，
// 仅供无邮件 / 短信通道的联调环境使用。
func DevCodeEnabled() bool {
	return strings.TrimSpace(os.Getenv("ACCOUNT_DEV_CODE")) == "1"
}

// Configured 判断渠道是否可用。
func (s *Service) Configured(channel string) bool {
	switch channel {
	case ChannelEmail:
		return s.mail.Configured()
	case ChannelPhone:
		return s.sms.Configured()
	}
	return false
}

// Send 投递验证码。未配置渠道时写日志并返回 ErrNotConfigured，由调用方决定如何提示。
func (s *Service) Send(ctx context.Context, channel, target, code, purpose string) error {
	switch channel {
	case ChannelEmail:
		if !s.mail.Configured() {
			log.Printf("[notify] 邮件通道未配置，验证码仅记录日志: %s -> %s", maskTarget(target), code)
			return ErrNotConfigured
		}
		return s.sendMail(target, code, purpose)
	case ChannelPhone:
		if !s.sms.Configured() {
			log.Printf("[notify] 短信通道未配置，验证码仅记录日志: %s -> %s", maskTarget(target), code)
			return ErrNotConfigured
		}
		return s.sendSMS(ctx, target, code, purpose)
	}
	return fmt.Errorf("未知投递渠道: %s", channel)
}

// SendMail 发送一封自定义内容的邮件（后台「发送测试邮件」复用）。
func (s *Service) SendMail(to, subject, body string) error {
	if s.mail.Host == "" || s.mail.From == "" {
		return ErrNotConfigured
	}
	return s.deliver(to, subject, body)
}

// SendSMS 发送一条自定义短信（后台「发送测试短信」复用）。
func (s *Service) SendSMS(ctx context.Context, phone, text string) error {
	if !s.sms.Configured() {
		return ErrNotConfigured
	}
	return s.postSMS(ctx, phone, text, "test", "")
}

func (s *Service) sendMail(to, code, purpose string) error {
	vars := s.templateVars(to, code, purpose)
	subject := render(s.mail.Template.Subject, vars)
	body := render(s.mail.Template.Body, vars)
	return s.deliver(to, subject, body)
}

func (s *Service) deliver(to, subject, body string) error {
	from := s.mail.From
	header := "From: " + from + "\r\n"
	if name := strings.TrimSpace(s.mail.FromName); name != "" {
		header = "From: " + mime.QEncoding.Encode("utf-8", name) + " <" + from + ">\r\n"
	}

	var buf bytes.Buffer
	buf.WriteString(header)
	buf.WriteString("To: " + to + "\r\n")
	buf.WriteString("Subject: " + mime.QEncoding.Encode("utf-8", subject) + "\r\n")
	buf.WriteString("MIME-Version: 1.0\r\n")
	buf.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	buf.WriteString("Content-Transfer-Encoding: 8bit\r\n\r\n")
	buf.WriteString(body)

	var auth smtp.Auth
	if s.mail.User != "" {
		auth = smtp.PlainAuth("", s.mail.User, s.mail.Pass, s.mail.Host)
	}
	port := integration.ParsePort(s.mail.Port, 587)
	addr := s.mail.Host + ":" + strconv.Itoa(port)

	if strings.EqualFold(s.mail.Encryption, "ssl") {
		return sendMailTLS(addr, s.mail.Host, auth, from, to, buf.Bytes())
	}
	return smtp.SendMail(addr, auth, from, []string{to}, buf.Bytes())
}

func (s *Service) sendSMS(ctx context.Context, phone, code, purpose string) error {
	text := render(s.sms.Template, s.templateVars(phone, code, purpose))
	return s.postSMS(ctx, phone, text, purpose, code)
}

func (s *Service) postSMS(ctx context.Context, phone, text, purpose, code string) error {
	payload, err := json.Marshal(map[string]string{
		"phone":   phone,
		"code":    code,
		"purpose": purpose,
		"text":    text,
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.sms.WebhookURL, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if token := strings.TrimSpace(s.sms.Token); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
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

// templateVars 模板可用变量。
func (s *Service) templateVars(target, code, purpose string) map[string]string {
	return map[string]string{
		"site":    s.site,
		"code":    code,
		"purpose": purposeLabel(purpose),
		"expires": "10",
		"target":  target,
		"email":   target,
		"phone":   target,
	}
}

// render 替换 {{name}} / {{ name }} 形式的占位符，未知占位符原样保留便于排查。
func render(tpl string, vars map[string]string) string {
	out := tpl
	for k, v := range vars {
		out = strings.ReplaceAll(out, "{{"+k+"}}", v)
		out = strings.ReplaceAll(out, "{{ "+k+" }}", v)
	}
	return out
}

func purposeLabel(purpose string) string {
	switch purpose {
	case PurposeReset:
		return "找回密码"
	case PurposeBind:
		return "账号绑定"
	case "test":
		return "通道测试"
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
