package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthHandler_ReturnsOK(t *testing.T) {
	targets := &mockTargets{hashes: map[string]bool{"a": true, "b": true}}
	h := HealthHandler(targets)

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["status"] != "ok" {
		t.Fatalf("expected status ok, got %v", resp["status"])
	}
	if resp["targets_loaded"] != float64(2) {
		t.Fatalf("expected targets_loaded 2, got %v", resp["targets_loaded"])
	}
}

func TestHealthHandler_MethodNotAllowed(t *testing.T) {
	targets := &mockTargets{hashes: map[string]bool{}}
	h := HealthHandler(targets)

	req := httptest.NewRequest(http.MethodPost, "/healthz", nil)
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}
