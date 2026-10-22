package store

import (
	"context"

	"video-collection-service/pkg/collector"
)

// WriteBusinessRecord wraps the existing article/record and video writers with
// registry validation. Custom table writes are atomic with audit in SaveCollectionRecord.
func WriteBusinessRecord(ctx context.Context, s Store, r CollectionRecord, skip bool, sourceName string) (bool, error) {
	b, err := s.GetBusinessType(ctx, r.Target)
	if err != nil {
		return false, err
	}
	if _, err = ValidateBusinessValues(b, r.Values); err != nil {
		return false, err
	}
	if b.Writer == "video" {
		if skip {
			exists, err := s.HasCollectionRecord(ctx, r.SourceID, r.Target, r.Key)
			if err != nil {
				return false, err
			}
			if exists {
				return false, nil
			}
		}
		v := r.Values
		vod := collector.CleanedVod{
			SourceID:       r.SourceID,
			SourceName:     sourceName,
			Name:           v["title"],
			SubName:        v["sub_name"],
			Content:        v["content"],
			Picture:        v["cover"],
			TargetTypeName: v["category"],
			Year:           v["year"],
			Actor:          v["actor"],
			Director:       v["director"],
			Area:           v["area"],
			Remarks:        v["remarks"],
		}
		vod.SourceTypeName = v["category"]
		playURL := v["play_url"]
		if playURL != "" {
			playFrom := v["play_from"]
			if playFrom == "" {
				playFrom = "m3u8"
			}
			groups := collector.ParsePlayGroups(playFrom, v["play_server"], v["play_note"], playURL)
			for i := range groups {
				if groups[i].SourceID == "" {
					groups[i].SourceID = r.SourceID
				}
				if groups[i].SourceName == "" {
					groups[i].SourceName = sourceName
				}
			}
			vod.PlayGroups = groups
		}
		id, err := s.UpsertVideo(ctx, r.SourceID, &vod)
		if err != nil {
			return false, err
		}
		r.ContentID = id
	}
	return s.SaveCollectionRecord(ctx, r, skip)
}
