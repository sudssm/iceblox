package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

type mockReportStore struct {
	called bool
	report *Report
	err    error
	nextID int64
}

func (m *mockReportStore) CreateReport(_ context.Context, report *Report) error {
	m.called = true
	m.report = report
	if m.err != nil {
		return m.err
	}
	m.nextID++
	report.ID = m.nextID
	return nil
}

type mockStopICESubmitter struct {
	called      bool
	reportID    int64
	plateNumber string
	description string
	lat, lng    float64
}

func (m *mockStopICESubmitter) SubmitAsync(reportID int64, plateNumber, description string, lat, lng float64) {
	m.called = true
	m.reportID = reportID
	m.plateNumber = plateNumber
	m.description = description
	m.lat = lat
	m.lng = lng
}

func createMultipartRequest(t *testing.T, fields map[string]string, photoContent []byte) *http.Request {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)

	for k, v := range fields {
		if err := w.WriteField(k, v); err != nil {
			t.Fatalf("write field %s: %v", k, err)
		}
	}

	if photoContent != nil {
		part, err := w.CreateFormFile("photo", "test.jpg")
		if err != nil {
			t.Fatalf("create photo part: %v", err)
		}
		if _, err := part.Write(photoContent); err != nil {
			t.Fatalf("write photo: %v", err)
		}
	}

	if err := w.Close(); err != nil {
		t.Fatalf("close writer: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/reports", &buf)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("X-Device-ID", "test-device")
	return req
}

func TestReportsHandler_ValidSubmission(t *testing.T) {
	uploadDir := t.TempDir()
	store := &mockReportStore{}
	submitter := &mockStopICESubmitter{}
	h := ReportsHandler(store, uploadDir, submitter)

	fields := map[string]string{
		"description":  "ICE vehicle blocking bike lane",
		"latitude":     "40.7128",
		"longitude":    "-74.0060",
		"plate_number": "ABC123",
	}
	req := createMultipartRequest(t, fields, []byte("fake-jpeg-data"))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp["status"] != "ok" {
		t.Errorf("expected status ok, got %v", resp["status"])
	}
	if resp["report_id"] == nil {
		t.Error("expected report_id in response")
	}

	if !store.called {
		t.Fatal("expected store.CreateReport to be called")
	}
	if store.report.Description != "ICE vehicle blocking bike lane" {
		t.Errorf("unexpected description: %s", store.report.Description)
	}
	if store.report.PlateNumber != "ABC123" {
		t.Errorf("unexpected plate number: %s", store.report.PlateNumber)
	}
	if store.report.StopICEStatus != "pending" {
		t.Errorf("unexpected status: %s", store.report.StopICEStatus)
	}

	files, err := os.ReadDir(uploadDir)
	if err != nil {
		t.Fatalf("read upload dir: %v", err)
	}
	if len(files) != 1 {
		t.Fatalf("expected 1 file in upload dir, got %d", len(files))
	}
	if ext := filepath.Ext(files[0].Name()); ext != ".jpg" {
		t.Errorf("expected .jpg extension, got %s", ext)
	}

	if !submitter.called {
		t.Fatal("expected StopICE submitter to be called")
	}
	if submitter.plateNumber != "ABC123" {
		t.Errorf("unexpected plate sent to StopICE: %s", submitter.plateNumber)
	}
}

func TestReportsHandler_WithoutPlateNumber(t *testing.T) {
	uploadDir := t.TempDir()
	store := &mockReportStore{}
	h := ReportsHandler(store, uploadDir, nil)

	fields := map[string]string{
		"description": "suspicious vehicle",
		"latitude":    "34.0522",
		"longitude":   "-118.2437",
	}
	req := createMultipartRequest(t, fields, []byte("photo-data"))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if store.report.PlateNumber != "" {
		t.Errorf("expected empty plate number, got %s", store.report.PlateNumber)
	}
}

func TestReportsHandler_MissingDescription(t *testing.T) {
	uploadDir := t.TempDir()
	store := &mockReportStore{}
	h := ReportsHandler(store, uploadDir, nil)

	fields := map[string]string{
		"latitude":  "40.0",
		"longitude": "-74.0",
	}
	req := createMultipartRequest(t, fields, []byte("photo"))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestReportsHandler_MissingPhoto(t *testing.T) {
	uploadDir := t.TempDir()
	store := &mockReportStore{}
	h := ReportsHandler(store, uploadDir, nil)

	fields := map[string]string{
		"description": "test",
		"latitude":    "40.0",
		"longitude":   "-74.0",
	}
	req := createMultipartRequest(t, fields, nil)
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestReportsHandler_MissingDeviceID(t *testing.T) {
	uploadDir := t.TempDir()
	store := &mockReportStore{}
	h := ReportsHandler(store, uploadDir, nil)

	fields := map[string]string{
		"description": "test",
		"latitude":    "40.0",
		"longitude":   "-74.0",
	}
	req := createMultipartRequest(t, fields, []byte("photo"))
	req.Header.Del("X-Device-ID")
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestReportsHandler_InvalidLatitude(t *testing.T) {
	uploadDir := t.TempDir()
	store := &mockReportStore{}
	h := ReportsHandler(store, uploadDir, nil)

	fields := map[string]string{
		"description": "test",
		"latitude":    "not-a-number",
		"longitude":   "-74.0",
	}
	req := createMultipartRequest(t, fields, []byte("photo"))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestReportsHandler_LatitudeOutOfRange(t *testing.T) {
	uploadDir := t.TempDir()
	store := &mockReportStore{}
	h := ReportsHandler(store, uploadDir, nil)

	fields := map[string]string{
		"description": "test",
		"latitude":    "91.0",
		"longitude":   "-74.0",
	}
	req := createMultipartRequest(t, fields, []byte("photo"))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestReportsHandler_MethodNotAllowed(t *testing.T) {
	store := &mockReportStore{}
	h := ReportsHandler(store, t.TempDir(), nil)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/reports", nil)
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestReportsHandler_StoreError(t *testing.T) {
	uploadDir := t.TempDir()
	store := &mockReportStore{err: fmt.Errorf("db error")}
	h := ReportsHandler(store, uploadDir, nil)

	fields := map[string]string{
		"description": "test",
		"latitude":    "40.0",
		"longitude":   "-74.0",
	}
	req := createMultipartRequest(t, fields, []byte("photo"))
	w := httptest.NewRecorder()

	h(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}
}
