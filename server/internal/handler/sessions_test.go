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

type mockSessionEnder struct {
	sessionID    string
	maxDetConf   float64
	totalDetConf float64
	maxOCRConf   float64
	totalOCRConf float64
	calls        int
	err          error
}

func (m *mockSessionEnder) EndSession(_ context.Context, sessionID string, maxDetConf, totalDetConf, maxOCRConf, totalOCRConf float64) error {
	m.calls++
	m.sessionID = sessionID
	m.maxDetConf = maxDetConf
	m.totalDetConf = totalDetConf
	m.maxOCRConf = maxOCRConf
	m.totalOCRConf = totalOCRConf
	return m.err
}

func TestEndSessionHandler_ValidRequest(t *testing.T) {
	ender := &mockSessionEnder{}
	h := EndSessionHandler(ender)

	body := `{"session_id":"sess-123"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sessions/end", strings.NewReader(body))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]string
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if resp["status"] != "ok" {
		t.Errorf("expected status ok, got %s", resp["status"])
	}
	if ender.calls != 1 {
		t.Errorf("expected 1 EndSession call, got %d", ender.calls)
	}
	if ender.sessionID != "sess-123" {
		t.Errorf("expected session_id sess-123, got %s", ender.sessionID)
	}
}

func TestEndSessionHandler_MethodNotAllowed(t *testing.T) {
	ender := &mockSessionEnder{}
	h := EndSessionHandler(ender)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions/end", nil)
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestEndSessionHandler_InvalidJSON(t *testing.T) {
	ender := &mockSessionEnder{}
	h := EndSessionHandler(ender)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/sessions/end", strings.NewReader("not json"))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestEndSessionHandler_EmptySessionID(t *testing.T) {
	ender := &mockSessionEnder{}
	h := EndSessionHandler(ender)

	body := `{"session_id":""}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sessions/end", strings.NewReader(body))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
	if ender.calls != 0 {
		t.Errorf("expected 0 EndSession calls, got %d", ender.calls)
	}
}

func TestEndSessionHandler_StoreErrorStillReturns200(t *testing.T) {
	ender := &mockSessionEnder{err: fmt.Errorf("db error")}
	h := EndSessionHandler(ender)

	body := `{"session_id":"sess-fail"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sessions/end", strings.NewReader(body))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 even with store error, got %d: %s", w.Code, w.Body.String())
	}
}

func TestEndSessionHandler_ConfidenceStatsPassedThrough(t *testing.T) {
	ender := &mockSessionEnder{}
	h := EndSessionHandler(ender)

	body := `{"session_id":"sess-conf","max_detection_confidence":0.95,"total_detection_confidence":42.5,"max_ocr_confidence":0.88,"total_ocr_confidence":35.2}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sessions/end", strings.NewReader(body))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if ender.maxDetConf != 0.95 {
		t.Errorf("max_detection_confidence: got %f, want 0.95", ender.maxDetConf)
	}
	if ender.totalDetConf != 42.5 {
		t.Errorf("total_detection_confidence: got %f, want 42.5", ender.totalDetConf)
	}
	if ender.maxOCRConf != 0.88 {
		t.Errorf("max_ocr_confidence: got %f, want 0.88", ender.maxOCRConf)
	}
	if ender.totalOCRConf != 35.2 {
		t.Errorf("total_ocr_confidence: got %f, want 35.2", ender.totalOCRConf)
	}
}
