package handler

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

var errTest = errors.New("test error")

type mockMapSightingQuerier struct {
	sightings []MapSightingEntry
	reports   []MapReportEntry
	queryErr  error
}

func (m *mockMapSightingQuerier) MapSightings(_ context.Context, _, _, _, _ float64, _ time.Time) ([]MapSightingEntry, error) {
	if m.queryErr != nil {
		return nil, m.queryErr
	}
	return m.sightings, nil
}

func (m *mockMapSightingQuerier) MapReports(_ context.Context, _, _, _, _ float64, _ time.Time) ([]MapReportEntry, error) {
	if m.queryErr != nil {
		return nil, m.queryErr
	}
	return m.reports, nil
}

type mockPhotoSigner struct {
	url string
	err error
}

func (m *mockPhotoSigner) PresignedPhotoURL(_ context.Context, key string) (string, error) {
	if m.err != nil {
		return "", m.err
	}
	if m.url != "" {
		return m.url, nil
	}
	return "https://bucket.s3.amazonaws.com/" + key + "?signed=1", nil
}

func TestMapSightingsHandler_ValidRequest(t *testing.T) {
	now := time.Now().UTC()
	querier := &mockMapSightingQuerier{
		sightings: []MapSightingEntry{
			{Latitude: 40.71, Longitude: -74.00, SeenAt: now},
		},
		reports: []MapReportEntry{
			{Latitude: 40.72, Longitude: -74.01, CreatedAt: now, Description: "Black SUV", PhotoPath: "reports/abc.jpg"},
		},
	}
	signer := &mockPhotoSigner{}
	h := MapSightingsHandler(querier, signer)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/map-sightings?lat=40.71&lng=-74.00&radius=10", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp mapSightingsResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.Status != "ok" {
		t.Errorf("expected status ok, got %s", resp.Status)
	}
	if len(resp.Sightings) != 2 {
		t.Fatalf("expected 2 sightings, got %d", len(resp.Sightings))
	}

	s := resp.Sightings[0]
	if s.Type != "sighting" {
		t.Errorf("expected type sighting, got %s", s.Type)
	}
	if s.Latitude != 40.71 {
		t.Errorf("expected latitude 40.71, got %f", s.Latitude)
	}
	if s.Confidence != 1.0 {
		t.Errorf("expected confidence 1.0, got %f", s.Confidence)
	}

	r := resp.Sightings[1]
	if r.Type != "report" {
		t.Errorf("expected type report, got %s", r.Type)
	}
	if r.Description == nil || *r.Description != "Black SUV" {
		t.Errorf("expected description 'Black SUV', got %v", r.Description)
	}
	if r.PhotoURL == nil || *r.PhotoURL == "" {
		t.Error("expected photo_url to be set")
	}
}

func TestMapSightingsHandler_MethodNotAllowed(t *testing.T) {
	h := MapSightingsHandler(&mockMapSightingQuerier{}, nil)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/map-sightings?lat=40&lng=-74&radius=10", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Errorf("expected 405, got %d", w.Code)
	}
}

func TestMapSightingsHandler_MissingParams(t *testing.T) {
	h := MapSightingsHandler(&mockMapSightingQuerier{}, nil)

	tests := []struct {
		name  string
		query string
	}{
		{"missing lat", "?lng=-74&radius=10"},
		{"missing lng", "?lat=40&radius=10"},
		{"missing radius", "?lat=40&lng=-74"},
		{"invalid lat", "?lat=abc&lng=-74&radius=10"},
		{"invalid lng", "?lat=40&lng=abc&radius=10"},
		{"invalid radius", "?lat=40&lng=-74&radius=abc"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/v1/map-sightings"+tc.query, nil)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, req)
			if w.Code != http.StatusBadRequest {
				t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestMapSightingsHandler_OutOfRange(t *testing.T) {
	h := MapSightingsHandler(&mockMapSightingQuerier{}, nil)

	tests := []struct {
		name  string
		query string
	}{
		{"lat too low", "?lat=-91&lng=-74&radius=10"},
		{"lat too high", "?lat=91&lng=-74&radius=10"},
		{"lng too low", "?lat=40&lng=-181&radius=10"},
		{"lng too high", "?lat=40&lng=181&radius=10"},
		{"radius too low", "?lat=40&lng=-74&radius=0"},
		{"radius too high", "?lat=40&lng=-74&radius=501"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/v1/map-sightings"+tc.query, nil)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, req)
			if w.Code != http.StatusBadRequest {
				t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestMapSightingsHandler_EmptyResults(t *testing.T) {
	querier := &mockMapSightingQuerier{}
	h := MapSightingsHandler(querier, nil)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/map-sightings?lat=40&lng=-74&radius=10", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp mapSightingsResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Status != "ok" {
		t.Errorf("expected ok, got %s", resp.Status)
	}
	if len(resp.Sightings) != 0 {
		t.Errorf("expected empty sightings, got %d", len(resp.Sightings))
	}
}

func TestMapSightingsHandler_QueryError(t *testing.T) {
	querier := &mockMapSightingQuerier{queryErr: errTest}
	h := MapSightingsHandler(querier, nil)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/map-sightings?lat=40&lng=-74&radius=10", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", w.Code)
	}
}

func TestMapSightingsHandler_NoPhotoSigner(t *testing.T) {
	now := time.Now().UTC()
	querier := &mockMapSightingQuerier{
		reports: []MapReportEntry{
			{Latitude: 40.72, Longitude: -74.01, CreatedAt: now, Description: "SUV", PhotoPath: "reports/abc.jpg"},
		},
	}
	h := MapSightingsHandler(querier, nil)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/map-sightings?lat=40&lng=-74&radius=10", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp mapSightingsResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Sightings) != 1 {
		t.Fatalf("expected 1, got %d", len(resp.Sightings))
	}
	if resp.Sightings[0].PhotoURL != nil {
		t.Error("expected nil photo_url when no signer")
	}
}

func TestMapSightingsHandler_BoundaryValues(t *testing.T) {
	h := MapSightingsHandler(&mockMapSightingQuerier{}, nil)

	tests := []struct {
		name  string
		query string
	}{
		{"min lat", "?lat=-90&lng=0&radius=1"},
		{"max lat", "?lat=90&lng=0&radius=1"},
		{"min lng", "?lat=0&lng=-180&radius=1"},
		{"max lng", "?lat=0&lng=180&radius=1"},
		{"min radius", "?lat=0&lng=0&radius=1"},
		{"max radius", "?lat=0&lng=0&radius=500"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/v1/map-sightings"+tc.query, nil)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, req)
			if w.Code != http.StatusOK {
				t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
			}
		})
	}
}
