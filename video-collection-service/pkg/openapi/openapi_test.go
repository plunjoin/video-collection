package openapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestOpenAPISpecValidJSON(t *testing.T) {
	spec := GetSpec()
	if len(spec) == 0 {
		t.Fatal("OpenAPI spec is empty")
	}

	var parsed map[string]interface{}
	if err := json.Unmarshal(spec, &parsed); err != nil {
		t.Fatalf("OpenAPI spec is not valid JSON: %v", err)
	}

	if parsed["openapi"] != "3.0.3" {
		t.Errorf("Expected openapi 3.0.3, got %v", parsed["openapi"])
	}

	info, ok := parsed["info"].(map[string]interface{})
	if !ok {
		t.Fatal("info section missing or not an object")
	}
	if info["title"] == "" {
		t.Error("info.title is empty")
	}

	paths, ok := parsed["paths"].(map[string]interface{})
	if !ok || len(paths) == 0 {
		t.Fatal("paths section missing or empty")
	}
}

func TestOpenAPIRoutes(t *testing.T) {
	mux := http.NewServeMux()
	RegisterRoutes(mux)

	// Test /openapi.json
	req := httptest.NewRequest(http.MethodGet, "/openapi.json", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Expected status 200 for /openapi.json, got %d", rec.Code)
	}
	contentType := rec.Header().Get("Content-Type")
	if !strings.Contains(contentType, "application/json") {
		t.Errorf("Expected application/json, got %s", contentType)
	}

	// Test /docs (Swagger UI)
	reqDocs := httptest.NewRequest(http.MethodGet, "/docs", nil)
	recDocs := httptest.NewRecorder()
	mux.ServeHTTP(recDocs, reqDocs)

	if recDocs.Code != http.StatusOK {
		t.Errorf("Expected status 200 for /docs, got %d", recDocs.Code)
	}
	if !strings.Contains(recDocs.Body.String(), "swagger-ui") {
		t.Errorf("Expected Swagger UI HTML content in /docs")
	}

	// Test /redoc
	reqRedoc := httptest.NewRequest(http.MethodGet, "/redoc", nil)
	recRedoc := httptest.NewRecorder()
	mux.ServeHTTP(recRedoc, reqRedoc)

	if recRedoc.Code != http.StatusOK {
		t.Errorf("Expected status 200 for /redoc, got %d", recRedoc.Code)
	}
	if !strings.Contains(recRedoc.Body.String(), "redoc") {
		t.Errorf("Expected Redoc HTML content in /redoc")
	}
}

func TestContentAPIContract(t *testing.T) {
	var spec struct {
		Paths      map[string]map[string]json.RawMessage `json:"paths"`
		Components struct {
			Schemas         map[string]json.RawMessage `json:"schemas"`
			SecuritySchemes map[string]struct {
				Name string `json:"name"`
			} `json:"securitySchemes"`
		} `json:"components"`
	}
	if err := json.Unmarshal(GetSpec(), &spec); err != nil {
		t.Fatal(err)
	}
	for path, methods := range map[string][]string{
		"/api/comments":                        {"get", "post", "delete"},
		"/api/admin/comments":                  {"get", "delete"},
		"/api/comments/likes":                  {"post", "delete"},
		"/api/news":                            {"get"},
		"/api/admin/news":                      {"get", "post", "delete"},
		"/api/community/posts":                 {"get", "post", "delete"},
		"/api/admin/community/posts":           {"get", "post", "delete"},
		"/api/community/comments":              {"get", "post", "delete"},
		"/api/admin/community/comments":        {"get", "delete"},
		"/api/community/likes":                 {"post", "delete"},
		"/api/user/notifications":              {"get", "delete"},
		"/api/user/notifications/unread-count": {"get"},
		"/api/user/notifications/read":         {"post"},
		"/api/admin/notifications":             {"post"},
	} {
		for _, method := range methods {
			var operation struct {
				Responses   map[string]json.RawMessage `json:"responses"`
				RequestBody json.RawMessage            `json:"requestBody"`
			}
			data, ok := spec.Paths[path][method]
			if !ok {
				t.Errorf("missing %s %s", method, path)
				continue
			}
			if err := json.Unmarshal(data, &operation); err != nil {
				t.Fatal(err)
			}
			if len(operation.Responses["200"]) == 0 || len(operation.Responses["400"]) == 0 {
				t.Errorf("missing response contracts for %s %s", method, path)
			}
			if method == "post" && len(operation.RequestBody) == 0 {
				t.Errorf("missing request contract for %s", path)
			}
		}
	}
	for _, name := range []string{"Comment", "GenericCommentCreateRequest", "CommentLikeRequest", "ContentRecord", "CommunityComment", "Notification", "NewsSaveRequest", "CommunityPostSaveRequest", "NotificationSendRequest", "NotificationReadRequest"} {
		if len(spec.Components.Schemas[name]) == 0 {
			t.Errorf("missing schema %s", name)
		}
	}
	if spec.Components.SecuritySchemes["CookieAuth"].Name != "agg_auth_token" {
		t.Error("cookie auth name does not match runtime")
	}
}
