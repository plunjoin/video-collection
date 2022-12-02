package m3u8cleaner

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
)

func TestExtractTSSeq(t *testing.T) {
	for _, tt := range []struct {
		uri  string
		want int64
		ok   bool
	}{
		{"seg_01.ts", 1, true},
		{"825e24e3d9e000073.ts", 73, true},
		{"c3a80713015000073.ts", 80713015000073, true},
		{"https://cdn.example.com/hls/c3a807130150673349.ts?token=123", 807130150673349, true},
		{"seg_9223372036854775807.m4s", 9223372036854775807, true},
		{"seg_9223372036854775808.ts", -1, false},
		{"seg_1234567890123456789012345.ts", -1, false},
		{"movie.ts", -1, false},
	} {
		t.Run(tt.uri, func(t *testing.T) {
			got, ok := extractTSSeq(tt.uri)
			if got != tt.want || ok != tt.ok {
				t.Fatalf("extractTSSeq(%q) = (%d, %t), want (%d, %t)", tt.uri, got, ok, tt.want, tt.ok)
			}
		})
	}
}

// Synthetic regression fixture with long numeric segment names.
// The seven ad segments interrupt movie segments 73 and 74 for 25.7 seconds.
func TestHandler_LongSequencePlaylist(t *testing.T) {
	raw, err := os.ReadFile("testdata/lz_long_sequence.m3u8")
	if err != nil {
		t.Fatal(err)
	}
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(raw)
	}))
	defer upstream.Close()

	for _, mode := range []string{"enabled", "disabled", "middle-disabled", "duration-limit"} {
		t.Run(mode, func(t *testing.T) {
			opts := DefaultOptions()
			switch mode {
			case "disabled":
				opts.EnableFilter = false
			case "middle-disabled":
				opts.FilterMiddleAd = false
			case "duration-limit":
				opts.MaxMiddleAdDuration = 20
			}
			handler := NewHandler(opts)
			for _, cacheStatus := range []string{"MISS", "HIT"} {
				req := httptest.NewRequest(http.MethodGet, "/api/m3u8/clean?url="+url.QueryEscape(upstream.URL+"/hls/mixed.m3u8"), nil)
				rec := httptest.NewRecorder()
				handler.ServeHTTP(rec, req)
				if rec.Code != http.StatusOK || rec.Header().Get("X-M3U8-AdClean-Cache") != cacheStatus {
					t.Fatalf("unexpected response: status=%d, cache=%q", rec.Code, rec.Header().Get("X-M3U8-AdClean-Cache"))
				}
				var got []string
				for _, line := range strings.Split(rec.Body.String(), "\n") {
					if strings.HasPrefix(line, "http") {
						got = append(got, line)
					}
				}
				var want []string
				for i := 0; i <= 348; i++ {
					want = append(want, fmt.Sprintf("%s/hls/c3a80713015%06d.ts", upstream.URL, i))
					if i == 73 && mode != "enabled" {
						for ad := 673349; ad <= 673355; ad++ {
							want = append(want, fmt.Sprintf("%s/hls/c3a80713015%07d.ts", upstream.URL, ad))
						}
					}
				}
				if strings.Join(got, "\n") != strings.Join(want, "\n") {
					t.Fatalf("playlist segments differ: got %d, want %d; all movie segments must remain in order", len(got), len(want))
				}
				if strings.Count(rec.Body.String(), "#EXTINF:") != len(want) || !strings.HasSuffix(rec.Body.String(), "#EXT-X-ENDLIST") {
					t.Fatal("segment durations or playlist end marker missing")
				}
			}
		})
	}
}
