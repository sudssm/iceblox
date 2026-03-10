package stopice

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

func TestSubmitter_SuccessfulSubmission(t *testing.T) {
	var receivedForm map[string]string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
		if err := r.ParseForm(); err != nil { //nolint:gosec // test handler, body limited above
			t.Fatalf("parse form: %v", err)
		}
		receivedForm = make(map[string]string)
		for k := range r.PostForm {
			receivedForm[k] = r.PostForm.Get(k)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	var mu sync.Mutex
	var callbackStatus string
	var callbackID int64

	sub := NewSubmitter(server.URL, func(reportID int64, status, errMsg string) {
		mu.Lock()
		defer mu.Unlock()
		callbackID = reportID
		callbackStatus = status
	})

	sub.SubmitAsync(42, "ABC123", "parked in bike lane", 40.7128, -74.0060)

	time.Sleep(200 * time.Millisecond)

	mu.Lock()
	defer mu.Unlock()

	if callbackID != 42 {
		t.Errorf("expected report ID 42, got %d", callbackID)
	}
	if callbackStatus != "submitted" {
		t.Errorf("expected status submitted, got %s", callbackStatus)
	}
	if receivedForm["vehicle_license"] != "ABC123" {
		t.Errorf("expected vehicle_license ABC123, got %s", receivedForm["vehicle_license"])
	}
	if receivedForm["guest"] != "1" {
		t.Errorf("expected guest=1, got %s", receivedForm["guest"])
	}
	if receivedForm["comments"] != "parked in bike lane" {
		t.Errorf("expected comments to match, got %s", receivedForm["comments"])
	}
	if receivedForm["alert_token"] == "" {
		t.Error("expected alert_token to be set")
	}
}

func TestSubmitter_ServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	var mu sync.Mutex
	var callbackStatus string
	var callbackErr string

	sub := NewSubmitter(server.URL, func(reportID int64, status, errMsg string) {
		mu.Lock()
		defer mu.Unlock()
		callbackStatus = status
		callbackErr = errMsg
	})

	sub.SubmitAsync(1, "XYZ789", "blocking crosswalk", 34.0522, -118.2437)

	time.Sleep(200 * time.Millisecond)

	mu.Lock()
	defer mu.Unlock()

	if callbackStatus != "failed" {
		t.Errorf("expected status failed, got %s", callbackStatus)
	}
	if callbackErr == "" {
		t.Error("expected error message to be set")
	}
}

func TestSubmitter_ConnectionError(t *testing.T) {
	var mu sync.Mutex
	var callbackStatus string

	sub := NewSubmitter("http://127.0.0.1:1", func(reportID int64, status, errMsg string) {
		mu.Lock()
		defer mu.Unlock()
		callbackStatus = status
	})

	sub.SubmitAsync(2, "FAKE", "test", 0, 0)

	time.Sleep(500 * time.Millisecond)

	mu.Lock()
	defer mu.Unlock()

	if callbackStatus != "failed" {
		t.Errorf("expected status failed, got %s", callbackStatus)
	}
}
