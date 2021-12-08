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
