package handler

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRequestLoggingMiddleware_LogsSuccessfulRequests(t *testing.T) {
	var logs bytes.Buffer
	logger := log.New(&logs, "", 0)

	handler := RequestLoggingMiddleware(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	req.Header.Set("X-Device-ID", "device-123")
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}

	logText := logs.String()
	if strings.Contains(logText, "http_server_error") {
		t.Fatalf("did not expect server_error log for successful request: %s", logText)
	}
	if strings.Contains(logText, "http_panic") {
		t.Fatalf("did not expect panic log for successful request: %s", logText)
	}
	if !strings.Contains(logText, "http_request method=GET path=/healthz status=204") {
		t.Fatalf("expected request log entry, got %s", logText)
	}
	if !strings.Contains(logText, `device_id="device-123"`) {
		t.Fatalf("expected device id in request log, got %s", logText)
	}
	if !strings.Contains(logText, "duration_ms=") {
		t.Fatalf("expected duration in request log, got %s", logText)
	}
}

func TestRequestLoggingMiddleware_LogsServerErrors(t *testing.T) {
	var logs bytes.Buffer
	logger := log.New(&logs, "", 0)

	handler := RequestLoggingMiddleware(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusInternalServerError, "failed to record sighting")
	}))

	req := httptest.NewRequest(http.MethodPost, "/api/v1/plates", nil)
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}

	logText := logs.String()
	if !strings.Contains(logText, "http_server_error method=POST path=/api/v1/plates status=500") {
		t.Fatalf("expected explicit server error log, got %s", logText)
	}
	if !strings.Contains(logText, "http_request method=POST path=/api/v1/plates status=500") {
		t.Fatalf("expected request log for 500 response, got %s", logText)
	}
}

func TestRequestLoggingMiddleware_RecoversPanics(t *testing.T) {
	var logs bytes.Buffer
	logger := log.New(&logs, "", 0)

	handler := RequestLoggingMiddleware(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("boom")
	}))

	req := httptest.NewRequest(http.MethodGet, "/boom", nil)
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}

	var body map[string]string
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("failed to decode panic response body: %v", err)
	}
	if body["error"] != "internal server error" {
		t.Fatalf("expected internal server error body, got %v", body)
	}

	logText := logs.String()
	if !strings.Contains(logText, "http_panic method=GET path=/boom status=500") {
		t.Fatalf("expected panic log entry, got %s", logText)
	}
	if !strings.Contains(logText, "panic=boom") {
		t.Fatalf("expected panic value in log entry, got %s", logText)
	}
	if !strings.Contains(logText, "http_request method=GET path=/boom status=500") {
		t.Fatalf("expected request log for recovered panic, got %s", logText)
	}
}
