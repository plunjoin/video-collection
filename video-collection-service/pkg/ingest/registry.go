package ingest

import (
	"context"
	"fmt"
	"video-collection-service/pkg/store"
)

type TargetSchema struct {
	RequiredFields []string
	ValidateValues func(map[string]string) error
}
type TargetLookup func(string) (TargetSchema, error)

type TargetRegistry interface {
	GetBusinessType(context.Context, string) (*store.BusinessType, error)
}

// RegistryLookup injects the current registry without process-global mutable
// state, so previews, saved rules, and scheduled runs share the same schema.
func RegistryLookup(ctx context.Context, registry TargetRegistry) TargetLookup {
	return func(slug string) (TargetSchema, error) {
		b, err := registry.GetBusinessType(ctx, slug)
		if err != nil {
			return TargetSchema{}, err
		}
		schema := TargetSchema{}
		for _, f := range b.Fields {
			if f.Required {
				schema.RequiredFields = append(schema.RequiredFields, f.Name)
			}
		}
		schema.ValidateValues = func(values map[string]string) error { _, err := store.ValidateBusinessValues(b, values); return err }
		return schema, nil
	}
}

func targetSchema(target string, lookups []TargetLookup) (TargetSchema, error) {
	if len(lookups) > 0 && lookups[0] != nil {
		return lookups[0](target)
	}
	// Compatibility for standalone engine consumers. Service entry points always
	// inject RegistryLookup, including for the seeded built-in business types.
	switch target {
	case "record":
		return TargetSchema{}, nil
	case "article":
		return TargetSchema{RequiredFields: []string{"title", "content"}}, nil
	case "video":
		return TargetSchema{RequiredFields: []string{"title"}}, nil
	}
	return TargetSchema{}, fmt.Errorf("未知业务类型: %s", target)
}
