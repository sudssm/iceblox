package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

type memoryLogger struct {
	mu      sync.Mutex
	entries []PlateLogEntry
}

func (m *memoryLogger) WriteEntry(entry PlateLogEntry) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.entries = append(m.entries, entry)
	return nil
}

type mockTargets struct {
	hashes map[string]bool
}

func (m *mockTargets) Contains(hash string) bool {
	return m.hashes[hash]
}

func (m *mockTargets) Count() int {
	return len(m.hashes)
}

var validHash = "a3f8b2c1d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4f5061728394a5b6c7d8e9"

func TestPlatesHandler_ValidRequest(t *testing.T) {
	logger := &memoryLogger{}
	targets := &mockTargets{hashes: map[string]bool{}}
	h := PlatesHandler(logger, targets)

	body := `{"plate_hash":"` + validHash + `","latitude":31.7619,"longitude":-106.485}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["status"] != "ok" {
		t.Fatalf("expected status ok, got %s", resp["status"])
	}
	if resp["matched"] != false {
		t.Fatalf("expected matched false for non-target hash")
	}

	if len(logger.entries) != 1 {
		t.Fatalf("expected 1 log entry, got %d", len(logger.entries))
	}
	if logger.entries[0].PlateHash != validHash {
		t.Errorf("logged hash mismatch")
	}
	if logger.entries[0].Latitude != 31.7619 {
		t.Errorf("logged latitude mismatch")
	}
}

func TestPlatesHandler_MatchedTarget(t *testing.T) {
	logger := &memoryLogger{}
	targets := &mockTargets{hashes: map[string]bool{validHash: true}}
	h := PlatesHandler(logger, targets)

	body := `{"plate_hash":"` + validHash + `","latitude":31.7619,"longitude":-106.485}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["matched"] != true {
		t.Fatalf("expected matched true for target hash")
	}

	if !logger.entries[0].Matched {
		t.Errorf("expected logged entry to have matched=true")
	}
}

func TestPlatesHandler_MethodNotAllowed(t *testing.T) {
	logger := &memoryLogger{}
	targets := &mockTargets{hashes: map[string]bool{}}
	h := PlatesHandler(logger, targets)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/plates", nil)
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestPlatesHandler_InvalidJSON(t *testing.T) {
	logger := &memoryLogger{}
	targets := &mockTargets{hashes: map[string]bool{}}
	h := PlatesHandler(logger, targets)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader("not json"))
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestPlatesHandler_InvalidHash(t *testing.T) {
	tests := []struct {
		name string
		hash string
	}{
		{"too short", "abc123"},
		{"not hex", "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"},
		{"empty", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			logger := &memoryLogger{}
			targets := &mockTargets{hashes: map[string]bool{}}
			h := PlatesHandler(logger, targets)

			body := `{"plate_hash":"` + tt.hash + `","latitude":31.0,"longitude":-106.0}`
			req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
			w := httptest.NewRecorder()
			h(w, req)

			if w.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d", w.Code)
			}
		})
	}
}

func TestPlatesHandler_InvalidCoordinates(t *testing.T) {
	tests := []struct {
		name string
		lat  float64
		lng  float64
	}{
		{"latitude too high", 91.0, 0},
		{"latitude too low", -91.0, 0},
		{"longitude too high", 0, 181.0},
		{"longitude too low", 0, -181.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			logger := &memoryLogger{}
			targets := &mockTargets{hashes: map[string]bool{}}
			h := PlatesHandler(logger, targets)

			body, _ := json.Marshal(PlateRequest{
				PlateHash: validHash,
				Latitude:  tt.lat,
				Longitude: tt.lng,
			})
			req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(string(body)))
			w := httptest.NewRecorder()
			h(w, req)

			if w.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestPlatesHandler_BoundaryCoordinates(t *testing.T) {
	tests := []struct {
		name string
		lat  float64
		lng  float64
	}{
		{"max lat/lng", 90.0, 180.0},
		{"min lat/lng", -90.0, -180.0},
		{"zero", 0, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			logger := &memoryLogger{}
			targets := &mockTargets{hashes: map[string]bool{}}
			h := PlatesHandler(logger, targets)

			body, _ := json.Marshal(PlateRequest{
				PlateHash: validHash,
				Latitude:  tt.lat,
				Longitude: tt.lng,
			})
			req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(string(body)))
			w := httptest.NewRecorder()
			h(w, req)

			if w.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
			}
		})
	}
}
