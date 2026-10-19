package webhook

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
)

// 密钥信封加密：webhook 明文密钥以 AES-256-GCM 加密后落库，
// 验签时临时解密参与 HMAC 计算，任何 API 均不返回明文。
// 加密主密钥来源优先级：WEBHOOK_ENCRYPTION_KEY > ADMIN_INITIAL_PASSWORD > 内置默认派生值。
var (
	ErrSecretCorrupted = errors.New("webhook 密钥解密失败（加密主密钥可能已变更，请重新轮换密钥）")
)

const fallbackKeyMaterial = "video-collection-webhook-envelope-v1"

// encryptionKey 派生 256 位加密主密钥（确定性派生，保证重启后可解密）。
func encryptionKey() ([32]byte, error) {
	var key [32]byte
	material := strings.TrimSpace(os.Getenv("WEBHOOK_ENCRYPTION_KEY"))
	if material == "" {
		material = strings.TrimSpace(os.Getenv("ADMIN_INITIAL_PASSWORD"))
	}
	if material == "" {
		material = fallbackKeyMaterial
	}
	sum := sha256.Sum256([]byte(material))
	copy(key[:], sum[:])
	return key, nil
}

// EncryptSecret 将明文密钥加密为 base64(nonce || ciphertext)，用于持久化。
func EncryptSecret(plain string) (string, error) {
	if plain == "" {
		return "", fmt.Errorf("密钥为空")
	}
	key, err := encryptionKey()
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	sealed := gcm.Seal(nonce, nonce, []byte(plain), nil)
	return base64.StdEncoding.EncodeToString(sealed), nil
}

// DecryptSecret 解密 EncryptSecret 的输出，还原明文密钥。
func DecryptSecret(sealed string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(sealed))
	if err != nil {
		return "", ErrSecretCorrupted
	}
	key, err := encryptionKey()
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	if len(raw) < gcm.NonceSize() {
		return "", ErrSecretCorrupted
	}
	nonce, ct := raw[:gcm.NonceSize()], raw[gcm.NonceSize():]
	plain, err := gcm.Open(nil, nonce, ct, nil)
	if err != nil {
		return "", ErrSecretCorrupted
	}
	return string(plain), nil
}

// SecretHint 生成用于界面展示的密钥掩码（保留前 4 位，其余以 * 代替）。
func SecretHint(secret string) string {
	if len(secret) <= 4 {
		return strings.Repeat("*", len(secret))
	}
	return secret[:4] + strings.Repeat("*", 16)
}
