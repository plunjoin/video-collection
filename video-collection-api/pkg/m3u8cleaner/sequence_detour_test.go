package m3u8cleaner

import (
	"fmt"
	"strings"
	"testing"
)

func TestCleanM3U8_SequenceDetour(t *testing.T) {
	for _, tt := range []struct {
		name       string
		before     []string
		middle     []string
		after      []string
		duration   float64
		noBoundary bool
		disabled   bool
		remove     bool
	}{
		{name: "higher sequence with small jump", middle: []string{"movie15000090.ts", "movie15000091.ts"}, remove: true},
		{name: "lower sequence with small jump", middle: []string{"movie15000050.ts", "movie15000051.ts"}, remove: true},
		{name: "lower sequence with large jump", before: []string{"movie15000073.ts"}, middle: []string{"movie10000.ts", "movie10001.ts"}, remove: true},
		{name: "ordinary continuation", middle: []string{"movie15000074.ts", "movie15000075.ts"}, after: []string{"movie15000076.ts"}},
		{name: "no return to consecutive sequence", middle: []string{"movie15000090.ts"}, after: []string{"movie15000080.ts"}},
		{name: "group extrema are not boundaries", before: []string{"movie15000073.ts", "movie15000072.ts"}, middle: []string{"movie15000090.ts"}},
		{name: "unknown middle sequence", middle: []string{"movie15000090.ts", "unknown.ts"}},
		{name: "unknown boundary sequence", before: []string{"unknown.ts"}, middle: []string{"movie15000090.ts"}},
		{name: "middle overlaps boundary", middle: []string{"movie15000073.ts", "movie15000090.ts"}},
		{name: "middle straddles boundaries", middle: []string{"movie15000050.ts", "movie15000090.ts"}},
		{name: "over duration limit", middle: []string{"movie15000090.ts", "movie15000091.ts"}, duration: 46},
		{name: "no discontinuity", middle: []string{"movie15000090.ts"}, noBoundary: true},
		{name: "middle filter disabled", middle: []string{"movie15000090.ts"}, disabled: true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if tt.before == nil {
				// A normal movie group longer than the independent head-ad threshold.
				for seq := 15000058; seq <= 15000073; seq++ {
					tt.before = append(tt.before, fmt.Sprintf("movie%d.ts", seq))
				}
			}
			if tt.after == nil {
				tt.after = []string{"movie15000074.ts"}
			}
			if tt.duration == 0 {
				tt.duration = 4
			}
			var raw strings.Builder
			raw.WriteString("#EXTM3U\n")
			for i, group := range [][]string{tt.before, tt.middle, tt.after} {
				if i > 0 && !tt.noBoundary {
					raw.WriteString("#EXT-X-DISCONTINUITY\n")
				}
				for _, uri := range group {
					fmt.Fprintf(&raw, "#EXTINF:%.3f,\n%s\n", tt.duration, uri)
				}
			}
			raw.WriteString("#EXT-X-ENDLIST")
			opts := DefaultOptions()
			opts.FilterMiddleAd = !tt.disabled
			cleaned, err := CleanM3U8(raw.String(), "https://example.com/index.m3u8", opts)
			if err != nil {
				t.Fatal(err)
			}
			want := append([]string{}, tt.before...)
			if !tt.remove {
				want = append(want, tt.middle...)
			}
			want = append(want, tt.after...)
			var got []string
			for _, line := range strings.Split(cleaned, "\n") {
				if strings.HasPrefix(line, "https://example.com/") {
					got = append(got, strings.TrimPrefix(line, "https://example.com/"))
				}
			}
			if strings.Join(got, "\n") != strings.Join(want, "\n") {
				t.Fatalf("got segments %v, want %v", got, want)
			}
		})
	}
}
