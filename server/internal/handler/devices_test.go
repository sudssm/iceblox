package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type mockDeviceTokenStore struct {
	called     bool
	hardwareID string
	token      string
	platform   string
	err        error
}

func (m *mockDeviceTokenStore) UpsertDeviceToken(_ context.Context, hardwareID, token, platform string) error {
	m.called = true
	m.hardwareID = hardwareID
	m.token = token
	m.platform = platform
	return m.err
}

func TestDevicesHandler_ValidRegistration(t *testing.T) {
	store := &mockDeviceTokenStore{}
	h := DevicesHandler(store)

	body := `{"token":"abc123token","platform":"ios"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-42")
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]string
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp["status"] != "ok" {
		t.Errorf("expected status ok, got %s", resp["status"])
	}
	if !store.called {
		t.Fatal("expected store.UpsertDeviceToken to be called")
	}
	if store.hardwareID != "device-42" {
		t.Errorf("expected hardwareID device-42, got %s", store.hardwareID)
	}
	if store.token != "abc123token" {
		t.Errorf("expected token abc123token, got %s", store.token)
	}
	if store.platform != "ios" {
		t.Errorf("expected platform ios, got %s", store.platform)
	}
}

func TestDevicesHandler_AndroidPlatform(t *testing.T) {
	store := &mockDeviceTokenStore{}
	h := DevicesHandler(store)

	body := `{"token":"fcm-token-xyz","platform":"android"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "android-device")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if store.platform != "android" {
		t.Errorf("expected platform android, got %s", store.platform)
	}
}

func TestDevicesHandler_MissingDeviceID(t *testing.T) {
	store := &mockDeviceTokenStore{}
	h := DevicesHandler(store)

	body := `{"token":"abc","platform":"ios"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices", strings.NewReader(body))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
	if store.called {
		t.Fatal("store should not be called when X-Device-ID is missing")
	}
}

func TestDevicesHandler_MissingToken(t *testing.T) {
	store := &mockDeviceTokenStore{}
	h := DevicesHandler(store)

	body := `{"token":"","platform":"ios"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-1")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestDevicesHandler_InvalidPlatform(t *testing.T) {
	store := &mockDeviceTokenStore{}
	h := DevicesHandler(store)

	body := `{"token":"abc","platform":"windows"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-1")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestDevicesHandler_InvalidJSON(t *testing.T) {
	store := &mockDeviceTokenStore{}
	h := DevicesHandler(store)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices", strings.NewReader("not json"))
	req.Header.Set("X-Device-ID", "device-1")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestDevicesHandler_MethodNotAllowed(t *testing.T) {
	store := &mockDeviceTokenStore{}
	h := DevicesHandler(store)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/devices", nil)
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestDevicesHandler_StoreError(t *testing.T) {
	store := &mockDeviceTokenStore{err: fmt.Errorf("db error")}
	h := DevicesHandler(store)

	body := `{"token":"abc","platform":"ios"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices", strings.NewReader(body))
	req.Header.Set("X-Device-ID", "device-1")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}
}
