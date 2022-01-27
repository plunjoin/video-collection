package config

// PipelineRule separates transport, extraction and destination. Version is explicit
// so future adapters can evolve without silently changing saved rules.
type PipelineRule struct {
	Version    int                `json:"version" yaml:"version"`
	Input      string             `json:"input" yaml:"input"`   // api, html, database, file
	Target     string             `json:"target" yaml:"target"` // record, article, video
	KeyField   string             `json:"key_field" yaml:"key_field"`
	Duplicate  string             `json:"duplicate" yaml:"duplicate"` // update, skip
	MaxRecords int                `json:"max_records" yaml:"max_records"`
	Request    RequestRule        `json:"request" yaml:"request"`
	HTML       HTMLRule           `json:"html" yaml:"html"`
	Database   ImportDatabaseRule `json:"database" yaml:"database"`
	File       ImportFileRule     `json:"file" yaml:"file"`
	Fields     []FieldRule        `json:"fields" yaml:"fields"`
}

type RequestRule struct {
	Method    string `json:"method" yaml:"method"`
	Body      string `json:"body" yaml:"body"`
	ListPath  string `json:"list_path" yaml:"list_path"`
	PageParam string `json:"page_param" yaml:"page_param"`
	StartPage int    `json:"start_page" yaml:"start_page"`
}

type HTMLRule struct {
	ItemSelector   string `json:"item_selector" yaml:"item_selector"`
	DetailSelector string `json:"detail_selector" yaml:"detail_selector"`
	NextSelector   string `json:"next_selector" yaml:"next_selector"`
}

type ImportDatabaseRule struct {
	Driver string `json:"driver" yaml:"driver"`   // postgres, mysql, sqlite, sqlserver
	DSNEnv string `json:"dsn_env" yaml:"dsn_env"` // server-side secret, never returned
	Query  string `json:"query" yaml:"query"`
}

type ImportFileRule struct {
	Token     string `json:"token" yaml:"token"`
	Name      string `json:"name" yaml:"name"`
	Sheet     string `json:"sheet" yaml:"sheet"`
	HeaderRow int    `json:"header_row" yaml:"header_row"`
}

type FieldRule struct {
	Target      string `json:"target" yaml:"target"`
	Selector    string `json:"selector" yaml:"selector"`   // JSON dot path, column or CSS
	Attribute   string `json:"attribute" yaml:"attribute"` // HTML: text(default), html, href...
	Default     string `json:"default" yaml:"default"`
	Required    bool   `json:"required" yaml:"required"`
	Trim        bool   `json:"trim" yaml:"trim"`
	StripHTML   bool   `json:"strip_html" yaml:"strip_html"`
	Pattern     string `json:"pattern" yaml:"pattern"`
	Replacement string `json:"replacement" yaml:"replacement"`
}
