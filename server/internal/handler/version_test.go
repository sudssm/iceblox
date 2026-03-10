package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestAPIVersionMiddleware(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	wrapped := APIVersionMiddleware("v1")(inner)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/plates", nil)
	rec := httptest.NewRecorder()

	wrapped.ServeHTTP(rec, req)

	if got := rec.Header().Get("API-Version"); got != "v1" {
		t.Errorf("API-Version header = %q, want %q", got, "v1")
	}
}

func TestDeprecationMiddleware(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	sunset := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	wrapped := DeprecationMiddleware(sunset, "/api/v2/docs")(inner)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/plates", nil)
	rec := httptest.NewRecorder()

	wrapped.ServeHTTP(rec, req)

	if got := rec.Header().Get("Deprecation"); got != "true" {
		t.Errorf("Deprecation header = %q, want %q", got, "true")
	}
	wantSunset := "Tue, 01 Sep 2026 00:00:00 GMT"
	if got := rec.Header().Get("Sunset"); got != wantSunset {
		t.Errorf("Sunset header = %q, want %q", got, wantSunset)
	}
	wantLink := `</api/v2/docs>; rel="successor-version"`
	if got := rec.Header().Get("Link"); got != wantLink {
		t.Errorf("Link header = %q, want %q", got, wantLink)
	}
}

func TestDeprecationMiddlewareNoSuccessor(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	sunset := time.Date(2026, 12, 1, 0, 0, 0, 0, time.UTC)
	wrapped := DeprecationMiddleware(sunset, "")(inner)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/plates", nil)
	rec := httptest.NewRecorder()

	wrapped.ServeHTTP(rec, req)

	if got := rec.Header().Get("Deprecation"); got != "true" {
		t.Errorf("Deprecation header = %q, want %q", got, "true")
	}
	if got := rec.Header().Get("Link"); got != "" {
		t.Errorf("Link header should be empty when no successor, got %q", got)
	}
}
