package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type mockSubscriberStore struct {
	calls []mockSetCall
}

type mockSetCall struct {
	DeviceID    string
	Lat, Lng    float64
	RadiusMiles float64
}

func (m *mockSubscriberStore) Set(deviceID string, lat, lng, radiusMiles float64) {
	m.calls = append(m.calls, mockSetCall{
		DeviceID:    deviceID,
		Lat:         lat,
		Lng:         lng,
		RadiusMiles: radiusMiles,
	})
}

type mockSightingQuerier struct {
	sightings []SightingResult
	err       error
}

func (m *mockSightingQuerier) RecentSightings(_ context.Context, _, _, _, _ float64, _ time.Time) ([]SightingResult, error) {
	return m.sightings, m.err
}

type mockDeviceToucher struct {
	touched []string
	err     error
}

func (m *mockDeviceToucher) TouchDeviceToken(_ context.Context, hardwareID string) error {
	m.touched = append(m.touched, hardwareID)
	return m.err
}

func TestSubscribeHandler_ValidRequest(t *testing.T) {
	subs := &mockSubscriberStore{}
	querier := &mockSightingQuerier{
		sightings: []SightingResult{
			{
				Plate:     "ABC1234",
				Latitude:  36.16,
				Longitude: -86.78,
				SeenAt:    time.Date(2026, 3, 8, 14, 30, 0, 0, time.UTC),
			},
		},
	}
	toucher := &mockDeviceToucher{}
	h := SubscribeHandler(subs, querier, toucher)

	body := `{"latitude":36.16,"longitude":-86.78,"radius_miles":10}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-123")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp subscribeResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if resp.Status != "ok" {
		t.Errorf("expected status ok, got %s", resp.Status)
	}
	if len(resp.RecentSightings) != 1 {
		t.Fatalf("expected 1 sighting, got %d", len(resp.RecentSightings))
	}
	if resp.RecentSightings[0].Plate != "ABC1234" {
		t.Errorf("expected plate ABC1234, got %s", resp.RecentSightings[0].Plate)
	}

	if len(subs.calls) != 1 {
		t.Fatalf("expected 1 subscriber store call, got %d", len(subs.calls))
	}
	if subs.calls[0].DeviceID != "device-123" {
		t.Errorf("expected device-123, got %s", subs.calls[0].DeviceID)
	}
}

func TestSubscribeHandler_EmptyRecentSightings(t *testing.T) {
	subs := &mockSubscriberStore{}
	querier := &mockSightingQuerier{}
	h := SubscribeHandler(subs, querier, nil)

	body := `{"latitude":36.16,"longitude":-86.78,"radius_miles":10}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-123")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp subscribeResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if resp.RecentSightings == nil {
		t.Fatal("expected empty array, got null")
	}
	if len(resp.RecentSightings) != 0 {
		t.Errorf("expected 0 sightings, got %d", len(resp.RecentSightings))
	}
}

func TestSubscribeHandler_FiltersOutOfRadius(t *testing.T) {
	subs := &mockSubscriberStore{}
	querier := &mockSightingQuerier{
		sightings: []SightingResult{
			{Plate: "NEAR", Latitude: 36.17, Longitude: -86.79, SeenAt: time.Now()},
			{Plate: "FAR", Latitude: 34.05, Longitude: -118.24, SeenAt: time.Now()},
		},
	}
	h := SubscribeHandler(subs, querier, nil)

	body := `{"latitude":36.16,"longitude":-86.78,"radius_miles":10}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-123")
	w := httptest.NewRecorder()

	h(w, req)

	var resp subscribeResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if len(resp.RecentSightings) != 1 {
		t.Fatalf("expected 1 sighting after filtering, got %d", len(resp.RecentSightings))
	}
	if resp.RecentSightings[0].Plate != "NEAR" {
		t.Errorf("expected NEAR plate, got %s", resp.RecentSightings[0].Plate)
	}
}

func TestSubscribeHandler_MethodNotAllowed(t *testing.T) {
	h := SubscribeHandler(&mockSubscriberStore{}, &mockSightingQuerier{}, nil)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/subscribe", nil)
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestSubscribeHandler_MissingDeviceID(t *testing.T) {
	h := SubscribeHandler(&mockSubscriberStore{}, &mockSightingQuerier{}, nil)

	body := `{"latitude":36.16,"longitude":-86.78,"radius_miles":10}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader(body))
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestSubscribeHandler_InvalidJSON(t *testing.T) {
	h := SubscribeHandler(&mockSubscriberStore{}, &mockSightingQuerier{}, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader("not json"))
	req.Header.Set("X-Device-ID", "device-123")
	w := httptest.NewRecorder()
	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestSubscribeHandler_ValidationErrors(t *testing.T) {
	lat := func(v float64) *float64 { return &v }
	lng := func(v float64) *float64 { return &v }
	rad := func(v float64) *float64 { return &v }

	tests := []struct {
		name string
		body string
	}{
		{"missing latitude", `{"longitude":-86.78,"radius_miles":10}`},
		{"missing longitude", `{"latitude":36.16,"radius_miles":10}`},
		{"missing radius_miles", `{"latitude":36.16,"longitude":-86.78}`},
		{"latitude too high", fmt.Sprintf(`{"latitude":%f,"longitude":%f,"radius_miles":%f}`, *lat(91), *lng(-86.78), *rad(10))},
		{"latitude too low", fmt.Sprintf(`{"latitude":%f,"longitude":%f,"radius_miles":%f}`, *lat(-91), *lng(-86.78), *rad(10))},
		{"longitude too high", fmt.Sprintf(`{"latitude":%f,"longitude":%f,"radius_miles":%f}`, *lat(36.16), *lng(181), *rad(10))},
		{"longitude too low", fmt.Sprintf(`{"latitude":%f,"longitude":%f,"radius_miles":%f}`, *lat(36.16), *lng(-181), *rad(10))},
		{"radius too small", fmt.Sprintf(`{"latitude":%f,"longitude":%f,"radius_miles":%f}`, *lat(36.16), *lng(-86.78), *rad(0.5))},
		{"radius too large", fmt.Sprintf(`{"latitude":%f,"longitude":%f,"radius_miles":%f}`, *lat(36.16), *lng(-86.78), *rad(501))},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h := SubscribeHandler(&mockSubscriberStore{}, &mockSightingQuerier{}, nil)

			req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader(tt.body))
			req.Header.Set("X-Device-ID", "device-123")
			w := httptest.NewRecorder()
			h(w, req)

			if w.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestSubscribeHandler_BoundaryValues(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{"min valid radius", `{"latitude":0,"longitude":0,"radius_miles":1}`},
		{"max valid radius", `{"latitude":0,"longitude":0,"radius_miles":500}`},
		{"max latitude", `{"latitude":90,"longitude":0,"radius_miles":10}`},
		{"min latitude", `{"latitude":-90,"longitude":0,"radius_miles":10}`},
		{"max longitude", `{"latitude":0,"longitude":180,"radius_miles":10}`},
		{"min longitude", `{"latitude":0,"longitude":-180,"radius_miles":10}`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h := SubscribeHandler(&mockSubscriberStore{}, &mockSightingQuerier{}, nil)

			req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader(tt.body))
			req.Header.Set("X-Device-ID", "device-123")
			w := httptest.NewRecorder()
			h(w, req)

			if w.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestSubscribeHandler_QueryError(t *testing.T) {
	subs := &mockSubscriberStore{}
	querier := &mockSightingQuerier{err: fmt.Errorf("database error")}
	h := SubscribeHandler(subs, querier, nil)

	body := `{"latitude":36.16,"longitude":-86.78,"radius_miles":10}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-123")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}
}

func TestSubscribeHandler_SeenAtFormat(t *testing.T) {
	ts := time.Date(2026, 3, 8, 14, 30, 0, 0, time.UTC)
	subs := &mockSubscriberStore{}
	querier := &mockSightingQuerier{
		sightings: []SightingResult{
			{Plate: "ABC1234", Latitude: 36.16, Longitude: -86.78, SeenAt: ts},
		},
	}
	h := SubscribeHandler(subs, querier, nil)

	body := `{"latitude":36.16,"longitude":-86.78,"radius_miles":10}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-123")
	w := httptest.NewRecorder()

	h(w, req)

	var resp subscribeResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if resp.RecentSightings[0].SeenAt != "2026-03-08T14:30:00Z" {
		t.Errorf("expected RFC3339 timestamp, got %s", resp.RecentSightings[0].SeenAt)
	}
}

func TestSubscribeHandler_TouchesDeviceToken(t *testing.T) {
	subs := &mockSubscriberStore{}
	querier := &mockSightingQuerier{}
	toucher := &mockDeviceToucher{}
	h := SubscribeHandler(subs, querier, toucher)

	body := `{"latitude":36.16,"longitude":-86.78,"radius_miles":10}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/subscribe", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-xyz")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if len(toucher.touched) != 1 {
		t.Fatalf("expected 1 touch call, got %d", len(toucher.touched))
	}
	if toucher.touched[0] != "device-xyz" {
		t.Errorf("expected device-xyz, got %s", toucher.touched[0])
	}
}
