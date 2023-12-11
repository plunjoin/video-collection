package openapi

import (
	_ "embed"
	"encoding/json"
	"net/http"
	"strings"
)

//go:embed spec.json
var openAPISpec []byte

//go:embed growth-spec.json
var growthSpec []byte

func init() {
	var base, extra map[string]any
	if err := json.Unmarshal(openAPISpec, &base); err != nil {
		panic(err)
	}
	if err := json.Unmarshal(growthSpec, &extra); err != nil {
		panic(err)
	}
	for path, methods := range extra["paths"].(map[string]any) {
		base["paths"].(map[string]any)[path] = methods
	}
	for name, schema := range extra["components"].(map[string]any)["schemas"].(map[string]any) {
		base["components"].(map[string]any)["schemas"].(map[string]any)[name] = schema
	}
	base["tags"] = append(base["tags"].([]any), extra["tags"].([]any)...)
	var err error
	openAPISpec, err = json.MarshalIndent(base, "", "  ")
	if err != nil {
		panic(err)
	}
}

const swaggerUIHTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Video Collection API - OpenAPI 交互文档 (Swagger UI)</title>
  <link rel="stylesheet" type="text/css" href="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.18.2/swagger-ui.min.css" />
  <link rel="icon" type="image/png" href="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.18.2/favicon-32x32.png" sizes="32x32" />
  <style>
    html { box-sizing: border-box; overflow: -moz-scrollbars-vertical; overflow-y: scroll; }
    *, *:before, *:after { box-sizing: inherit; }
    body { margin: 0; background: #fafafa; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    .topbar { display: none; }
    .swagger-ui .info { margin: 24px 0; }
    .swagger-ui .info .title { font-size: 32px; font-weight: 700; color: #1e293b; }
    .header-bar {
      background: #0f172a;
      color: #fff;
      padding: 16px 24px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .header-bar h1 { margin: 0; font-size: 18px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
    .header-links a {
      color: #38bdf8;
      text-decoration: none;
      font-size: 14px;
      margin-left: 16px;
      padding: 4px 10px;
      border: 1px solid rgba(56,189,248,0.3);
      border-radius: 4px;
      transition: all 0.2s;
    }
    .header-links a:hover { background: rgba(56,189,248,0.1); border-color: #38bdf8; }
  </style>
</head>
<body>
  <div class="header-bar">
    <h1>🎬 视频采集与聚合系统 RESTful API 文档</h1>
    <div class="header-links">
      <a href="/openapi.json" target="_blank" download="openapi.json">📥 导出 OpenAPI Spec (JSON)</a>
      <a href="/redoc">📖 Redoc 视角</a>
    </div>
  </div>
  <div id="swagger-ui"></div>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.18.2/swagger-ui-bundle.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.18.2/swagger-ui-standalone-preset.min.js"></script>
  <script>
    window.onload = function() {
      window.ui = SwaggerUIBundle({
        url: "/openapi.json",
        dom_id: '#swagger-ui',
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        plugins: [
          SwaggerUIBundle.plugins.DownloadUrl
        ],
        layout: "StandaloneLayout",
        defaultModelsExpandDepth: 2,
        defaultModelExpandDepth: 2,
        docExpansion: "list",
        displayRequestDuration: true,
        filter: true,
        persistAuthorization: true
      });
    };
  </script>
</body>
</html>`

const redocHTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Video Collection API - OpenAPI 文档 (Redoc)</title>
  <link href="https://fonts.googleapis.com/css?family=Montserrat:300,400,700|Roboto:300,400,700" rel="stylesheet">
  <style>body { margin: 0; padding: 0; }</style>
</head>
<body>
  <redoc spec-url="/openapi.json"></redoc>
  <script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
</body>
</html>`

// RegisterRoutes 注册 OpenAPI 规范 JSON 及 Swagger / Redoc 交互文档路由
func RegisterRoutes(mux *http.ServeMux) {
	// 1. OpenAPI 3.0 Spec JSON 端点
	specHandler := func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(openAPISpec)
	}

	mux.HandleFunc("/openapi.json", specHandler)
	mux.HandleFunc("/api/openapi.json", specHandler)
	mux.HandleFunc("/v3/api-docs", specHandler)
	mux.HandleFunc("/swagger.json", specHandler)

	// 2. Swagger UI 交互式在线调试文档端点
	swaggerHandler := func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(swaggerUIHTML))
	}

	mux.HandleFunc("/docs", swaggerHandler)
	mux.HandleFunc("/docs/", swaggerHandler)
	mux.HandleFunc("/swagger", swaggerHandler)
	mux.HandleFunc("/swagger/", swaggerHandler)
	mux.HandleFunc("/swagger-ui", swaggerHandler)
	mux.HandleFunc("/swagger-ui.html", swaggerHandler)

	// 3. Redoc 静态文档端点
	redocHandler := func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(redocHTML))
	}
	mux.HandleFunc("/redoc", redocHandler)
	mux.HandleFunc("/redoc/", redocHandler)
}

// GetSpec 返回原始 OpenAPI Spec 字节数据
func GetSpec() []byte {
	return openAPISpec
}

// GetSpecString 返回格式化字符串
func GetSpecString() string {
	return strings.TrimSpace(string(openAPISpec))
}
