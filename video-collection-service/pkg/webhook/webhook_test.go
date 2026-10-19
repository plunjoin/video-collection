package webhook

import (
	"net/http"
	"testing"
	"time"
)

func TestSignatureRoundTrip(t *testing.T) {
	secret, err := GenerateSecret()
	if err != nil {
		t.Fatal(err)
	}
	body := []byte(`{"vod_name":"测试影片","vod_play_url":"https://example.com/1.m3u8"}`)
	sig := ComputeSignature(secret, body)
	if !VerifySignature(secret, sig, body) {
		t.Fatal("same secret must verify")
	}
	if !VerifySignature(secret, "sha256="+sig, body) {
		t.Fatal("prefixed signature must verify")
	}
	if !VerifySignature(secret, "  "+sig+" ", body) {
		t.Fatal("padded signature must verify")
	}
	if VerifySignature(secret, sig, []byte(`{"tampered":true}`)) {
		t.Error("modified body must fail")
	}
	if VerifySignature("another-secret", sig, body) {
		t.Error("wrong secret must fail")
	}
	if VerifySignature(secret, "", body) {
		t.Error("empty signature must fail")
	}
	if VerifySignature("", sig, body) {
		t.Error("empty secret must fail")
	}
	if NormalizeSignature("SHA256=ABC") != "abc" {
		t.Errorf("normalize prefix failed: %q", NormalizeSignature("SHA256=ABC"))
	}
}

func TestSecretEnvelope(t *testing.T) {
	plain, err := GenerateSecret()
	if err != nil {
		t.Fatal(err)
	}
	if len(plain) != 64 {
		t.Fatalf("secret length = %d, want 64", len(plain))
	}
	if plain == SecretHint(plain) {
		t.Error("hint must not equal secret")
	}
	sealed, err := EncryptSecret(plain)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := DecryptSecret(sealed); err != nil || got != plain {
		t.Fatalf("decrypt round trip failed: %q %v", got, err)
	}
	if _, err := DecryptSecret("not-base64!!"); err == nil {
		t.Error("corrupted envelope must fail")
	}
}

func TestPickSignatureHeaderPriority(t *testing.T) {
	h := http.Header{}
	h.Set("X-Signature", "a")
	h.Set("X-Webhook-Signature", "b")
	if got := PickSignatureHeader(h.Get, nil); got != "b" {
		t.Errorf("priority pick = %q, want b", got)
	}
	h2 := http.Header{}
	h2.Set("X-Signature", "only")
	if got := PickSignatureHeader(h2.Get, nil); got != "only" {
		t.Errorf("fallback pick = %q, want only", got)
	}
	if got := PickSignatureHeader(http.Header{}.Get, nil); got != "" {
		t.Errorf("empty pick = %q", got)
	}
}

func TestCheckTimestamp(t *testing.T) {
	now := time.Now()
	h := http.Header{}
	h.Set("X-Webhook-Timestamp", itoa(int(now.Unix())))
	res := CheckTimestamp(h.Get, 300, now)
	if !res.Provided || res.Reason != "" {
		t.Fatalf("unix timestamp rejected: %+v", res)
	}
	if !res.Timestamp.Equal(now.Truncate(time.Second)) {
		t.Errorf("timestamp = %v", res.Timestamp)
	}
	// 超出窗口
	h.Set("X-Webhook-Timestamp", strconvUnix(now.Add(-10*time.Minute)))
	res = CheckTimestamp(h.Get, 300, now)
	if res.Reason == "" {
		t.Error("stale timestamp must be rejected")
	}
	// 容忍窗口为 0 时不校验
	res = CheckTimestamp(h.Get, 0, now)
	if res.Reason != "" {
		t.Errorf("tolerance 0 must skip: %+v", res)
	}
	// 未携带
	res = CheckTimestamp(http.Header{}.Get, 300, now)
	if res.Provided || res.Reason != "" {
		t.Errorf("missing timestamp: %+v", res)
	}
	// 非法格式
	bad := http.Header{}
	bad.Set("X-Webhook-Timestamp", "yesterday")
	res = CheckTimestamp(bad.Get, 300, now)
	if res.Reason == "" {
		t.Error("garbage timestamp must be rejected")
	}
	// RFC3339
	rfc := http.Header{}
	rfc.Set("X-Webhook-Timestamp", now.Format(time.RFC3339))
	res = CheckTimestamp(rfc.Get, 300, now)
	if res.Reason != "" {
		t.Errorf("rfc3339 rejected: %+v", res)
	}
}

func strconvUnix(t time.Time) string {
	return itoa(int(t.Unix()))
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [24]byte
	i := len(buf)
	neg := n < 0
	if neg {
		n = -n
	}
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

func TestAllowsEvent(t *testing.T) {
	if !AllowsEvent(nil, "video.upsert") {
		t.Error("empty whitelist must allow all")
	}
	if !AllowsEvent([]string{"video.upsert"}, "VIDEO.UPSERT") {
		t.Error("event match must be case-insensitive")
	}
	if AllowsEvent([]string{"video.upsert"}, "video.delete") {
		t.Error("event not in whitelist must be denied")
	}
}

func TestRemoteAddr(t *testing.T) {
	if got := RemoteAddr("10.0.0.1:54321", ""); got != "10.0.0.1" {
		t.Errorf("got %q", got)
	}
	if got := RemoteAddr("10.0.0.1:54321", "1.2.3.4, 5.6.7.8"); got != "1.2.3.4" {
		t.Errorf("forwarded first = %q", got)
	}
	if got := RemoteAddr("", ""); got != "" {
		t.Errorf("empty = %q", got)
	}
}

func TestParsePayloadForms(t *testing.T) {
	cases := []struct {
		name string
		body string
		want int
	}{
		{"single vod", `{"vod_name":"影片A","vod_play_url":"a.m3u8"}`, 1},
		{"array", `[{"name":"影片B","play_url":"b.m3u8"},{"name":"影片C","play_url":"c.m3u8"}]`, 2},
		{"data list", `{"event":"x","data":{"list":[{"vod_name":"影片D","vod_play_url":"d.m3u8"}]}}`, 1},
		{"data array", `{"data":[{"vod_name":"影片E","vod_play_url":"e.m3u8"}]}`, 1},
		{"root list", `{"list":[{"vod_name":"影片F","vod_play_url":"f.m3u8"},{"vod_name":"影片G","vod_play_url":"g.m3u8"}]}`, 2},
		{"with event", `{"event":"video.upsert","data":{"list":[{"vod_name":"影片H","vod_play_url":"h.m3u8"}]}}`, 1},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			p, err := ParsePayload([]byte(c.body))
			if err != nil {
				t.Fatal(err)
			}
			if len(p.Videos) != c.want {
				t.Fatalf("videos = %d, want %d", len(p.Videos), c.want)
			}
			if p.Event == "" && c.name == "with event" {
				t.Error("event not parsed")
			}
			if p.Videos[0].Name == "" {
				t.Error("name not mapped")
			}
			if len(p.Videos[0].PlayGroups) == 0 {
				t.Error("play groups not parsed")
			}
		})
	}
}

func TestParsePayloadErrors(t *testing.T) {
	for _, body := range []string{``, `not-json`, `[1,2,3]`, `{"foo":"bar"}`} {
		if _, err := ParsePayload([]byte(body)); err == nil {
			t.Errorf("payload %q must fail", body)
		}
	}
}

func TestAttachSourceAndRecords(t *testing.T) {
	p, err := ParsePayload([]byte(`{"event":"e","data":{"list":[{"vod_name":"影片I","vod_play_from":"m3u8","vod_play_url":"i.m3u8"}]}}`))
	if err != nil {
		t.Fatal(err)
	}
	AttachSource(p.Videos, "webhook:wh_1", "回调源")
	if p.Videos[0].PlayGroups[0].SourceID != "webhook:wh_1" {
		t.Errorf("source id = %q", p.Videos[0].PlayGroups[0].SourceID)
	}
	if p.Videos[0].PlayGroups[0].SourceName != "回调源" {
		t.Errorf("source name = %q", p.Videos[0].PlayGroups[0].SourceName)
	}
	records := ToRecords(p)
	if len(records) != 1 || records[0]["title"] != "影片I" {
		t.Fatalf("records = %+v", records)
	}
}
