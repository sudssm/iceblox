package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type mockRecorder struct {
	mu        sync.Mutex
	sightings []mockSighting
}

type mockSighting struct {
	PlateID       int64
	SeenAt        time.Time
	Lat, Lng      float64
	HardwareID    string
	Substitutions int
}

func (m *mockRecorder) RecordSighting(_ context.Context, plateID int64, seenAt time.Time, lat, lng float64, hardwareID string, substitutions int) (int64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.sightings = append(m.sightings, mockSighting{
		PlateID: plateID, SeenAt: seenAt,
		Lat: lat, Lng: lng, HardwareID: hardwareID,
		Substitutions: substitutions,
	})
	return int64(len(m.sightings)), nil
}

type mockTargets struct {
	hashes map[string]int64
}

type mockNotifier struct {
	mu         sync.Mutex
	sightingID int64
	plateID    int64
	lat        float64
	lng        float64
	calls      int
}

func (m *mockTargets) Contains(hash string) bool {
	_, ok := m.hashes[hash]
	return ok
}

func (m *mockTargets) PlateID(hash string) (int64, bool) {
	id, ok := m.hashes[hash]
	return id, ok
}

func (m *mockTargets) Plate(hash string) (string, bool) {
	_, ok := m.hashes[hash]
	if !ok {
		return "", false
	}
	return "TESTPLATE", true
}

func (m *mockTargets) Count() int {
	return len(m.hashes)
}

func (m *mockNotifier) NotifyAsync(sightingID int64, plateID int64, lat, lng float64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.sightingID = sightingID
	m.plateID = plateID
	m.lat = lat
	m.lng = lng
	m.calls++
}

var validHash = "a3f8b2c1d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4f5061728394a5b6c7d8e9"

func batchBody(plates ...string) string {
	return `{"plates":[` + strings.Join(plates, ",") + `]}`
}

func TestPlatesHandler_ValidRequest(t *testing.T) {
	recorder := &mockRecorder{}
	targets := &mockTargets{hashes: map[string]int64{}}
	h := PlatesHandler(recorder, targets, nil)

	body := batchBody(`{"plate_hash":"` + validHash + `","latitude":31.7619,"longitude":-106.485}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if resp["status"] != "ok" {
		t.Fatalf("expected status ok, got %s", resp["status"])
	}
	results := resp["results"].([]interface{})
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].(map[string]interface{})["matched"] != false {
		t.Fatalf("expected matched false for non-target hash")
	}

	if len(recorder.sightings) != 0 {
		t.Fatalf("expected 0 sightings for non-match, got %d", len(recorder.sightings))
	}
}

func TestPlatesHandler_MatchedTarget(t *testing.T) {
	recorder := &mockRecorder{}
	targets := &mockTargets{hashes: map[string]int64{validHash: 42}}
	notifier := &mockNotifier{}
	h := PlatesHandler(recorder, targets, notifier)

	body := batchBody(`{"plate_hash":"` + validHash + `","latitude":31.7619,"longitude":-106.485,"timestamp":"2026-03-08T14:30:00Z"}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "test-device-123")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	results := resp["results"].([]interface{})
	if results[0].(map[string]interface{})["matched"] != true {
		t.Fatalf("expected matched true for target hash")
	}

	if len(recorder.sightings) != 1 {
		t.Fatalf("expected 1 sighting, got %d", len(recorder.sightings))
	}
	s := recorder.sightings[0]
	if s.PlateID != 42 {
		t.Errorf("expected plate_id 42, got %d", s.PlateID)
	}
	if s.Lat != 31.7619 {
		t.Errorf("expected lat 31.7619, got %f", s.Lat)
	}
	if s.HardwareID != "test-device-123" {
		t.Errorf("expected hardware_id test-device-123, got %s", s.HardwareID)
	}
	expected := time.Date(2026, 3, 8, 14, 30, 0, 0, time.UTC)
	if !s.SeenAt.Equal(expected) {
		t.Errorf("expected seen_at %v, got %v", expected, s.SeenAt)
	}
	if notifier.calls != 1 {
		t.Fatalf("expected notifier to be called once, got %d", notifier.calls)
	}
	if notifier.sightingID != 1 {
		t.Errorf("expected notifier sighting_id 1, got %d", notifier.sightingID)
	}
	if notifier.lat != 31.7619 || notifier.lng != -106.485 {
		t.Errorf("expected notifier coordinates (31.7619, -106.485), got (%f, %f)", notifier.lat, notifier.lng)
	}
}

func TestPlatesHandler_MatchedTarget_DefaultTimestamp(t *testing.T) {
	recorder := &mockRecorder{}
	targets := &mockTargets{hashes: map[string]int64{validHash: 1}}
	h := PlatesHandler(recorder, targets, nil)

	body := batchBody(`{"plate_hash":"` + validHash + `","latitude":31.7619,"longitude":-106.485}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
	w := httptest.NewRecorder()

	before := time.Now().UTC()
	h(w, req)

	if len(recorder.sightings) != 1 {
		t.Fatalf("expected 1 sighting, got %d", len(recorder.sightings))
	}
	if recorder.sightings[0].SeenAt.Before(before) {
		t.Error("expected default timestamp to be current server time")
	}
	if recorder.sightings[0].HardwareID != "unknown" {
		t.Errorf("expected default hardware_id 'unknown', got %s", recorder.sightings[0].HardwareID)
	}
}

func TestPlatesHandler_MethodNotAllowed(t *testing.T) {
	recorder := &mockRecorder{}
	targets := &mockTargets{hashes: map[string]int64{}}
	h := PlatesHandler(recorder, targets, nil)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/plates", nil)
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestPlatesHandler_InvalidJSON(t *testing.T) {
	recorder := &mockRecorder{}
	targets := &mockTargets{hashes: map[string]int64{}}
	h := PlatesHandler(recorder, targets, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader("not json"))
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestPlatesHandler_EmptyPlatesArray(t *testing.T) {
	recorder := &mockRecorder{}
	targets := &mockTargets{hashes: map[string]int64{}}
	h := PlatesHandler(recorder, targets, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(`{"plates":[]}`))
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
			recorder := &mockRecorder{}
			targets := &mockTargets{hashes: map[string]int64{}}
			h := PlatesHandler(recorder, targets, nil)

			body := batchBody(`{"plate_hash":"` + tt.hash + `","latitude":31.0,"longitude":-106.0}`)
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
			recorder := &mockRecorder{}
			targets := &mockTargets{hashes: map[string]int64{}}
			h := PlatesHandler(recorder, targets, nil)

			plate, _ := json.Marshal(PlateRequest{
				PlateHash: validHash,
				Latitude:  tt.lat,
				Longitude: tt.lng,
			})
			body := `{"plates":[` + string(plate) + `]}`
			req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
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
			recorder := &mockRecorder{}
			targets := &mockTargets{hashes: map[string]int64{}}
			h := PlatesHandler(recorder, targets, nil)

			plate, _ := json.Marshal(PlateRequest{
				PlateHash: validHash,
				Latitude:  tt.lat,
				Longitude: tt.lng,
			})
			body := `{"plates":[` + string(plate) + `]}`
			req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
			w := httptest.NewRecorder()
			h(w, req)

			if w.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestPlatesHandler_SubstitutionsStored(t *testing.T) {
	recorder := &mockRecorder{}
	targets := &mockTargets{hashes: map[string]int64{validHash: 42}}
	h := PlatesHandler(recorder, targets, nil)

	body := batchBody(`{"plate_hash":"` + validHash + `","latitude":31.7619,"longitude":-106.485,"substitutions":3}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "test-device")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	if len(recorder.sightings) != 1 {
		t.Fatalf("expected 1 sighting, got %d", len(recorder.sightings))
	}
	if recorder.sightings[0].Substitutions != 3 {
		t.Errorf("expected substitutions 3, got %d", recorder.sightings[0].Substitutions)
	}
}

func TestPlatesHandler_SubstitutionsDefaultZero(t *testing.T) {
	recorder := &mockRecorder{}
	targets := &mockTargets{hashes: map[string]int64{validHash: 42}}
	h := PlatesHandler(recorder, targets, nil)

	body := batchBody(`{"plate_hash":"` + validHash + `","latitude":31.7619,"longitude":-106.485}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "test-device")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	if len(recorder.sightings) != 1 {
		t.Fatalf("expected 1 sighting, got %d", len(recorder.sightings))
	}
	if recorder.sightings[0].Substitutions != 0 {
		t.Errorf("expected substitutions 0 (default), got %d", recorder.sightings[0].Substitutions)
	}
}

func TestPlatesHandler_MultiplePlates(t *testing.T) {
	hash2 := "b4f9c3d2e5f60819293a4b5c6d7e8f0a1b2c3d4e5f6071829304a5b6c7d8e9f0"
	recorder := &mockRecorder{}
	targets := &mockTargets{hashes: map[string]int64{validHash: 42}}
	notifier := &mockNotifier{}
	h := PlatesHandler(recorder, targets, notifier)

	body := batchBody(
		`{"plate_hash":"`+validHash+`","latitude":31.0,"longitude":-106.0}`,
		`{"plate_hash":"`+hash2+`","latitude":32.0,"longitude":-107.0}`,
	)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "dev1")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	results := resp["results"].([]interface{})
	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}
	if results[0].(map[string]interface{})["matched"] != true {
		t.Errorf("expected first plate matched")
	}
	if results[1].(map[string]interface{})["matched"] != false {
		t.Errorf("expected second plate not matched")
	}
	if len(recorder.sightings) != 1 {
		t.Fatalf("expected 1 sighting, got %d", len(recorder.sightings))
	}
	if notifier.calls != 1 {
		t.Errorf("expected 1 notifier call, got %d", notifier.calls)
	}
}
