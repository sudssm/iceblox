package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"iceblox/server/internal/handler"
	"iceblox/server/internal/targets"
)

type testRecorder struct {
	mu        sync.Mutex
	sightings []testSighting
}

type testSighting struct {
	PlateID    int64
	SeenAt     time.Time
	Lat, Lng   float64
	HardwareID string
}

func (r *testRecorder) RecordSighting(_ context.Context, plateID int64, seenAt time.Time, lat, lng float64, hardwareID string) (int64, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.sightings = append(r.sightings, testSighting{
		PlateID: plateID, SeenAt: seenAt,
		Lat: lat, Lng: lng, HardwareID: hardwareID,
	})
	return int64(len(r.sightings)), nil
}

// clientHMAC computes HMAC-SHA256 the same way a mobile client would,
// independent of the server's implementation.
func clientHMAC(plate string, pepper []byte) string {
	plate = strings.ToUpper(plate)
	plate = strings.ReplaceAll(plate, " ", "")
	plate = strings.ReplaceAll(plate, "-", "")
	// Filter to ASCII alphanumeric only (matches overview spec normalization)
	var filtered []byte
	for _, r := range []byte(plate) {
		if (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			filtered = append(filtered, r)
		}
	}
	mac := hmac.New(sha256.New, pepper)
	mac.Write(filtered)
	return hex.EncodeToString(mac.Sum(nil))
}

func TestEndToEnd_PlatesFileToAPIMatch(t *testing.T) {
	pepper := []byte("integration-test-pepper")

	dir := t.TempDir()
	platesPath := filepath.Join(dir, "plates.txt")
	err := os.WriteFile(platesPath, []byte(strings.Join([]string{
		"ABC123",
		"BRD1385",
		"C23896C",
		"DMG837",
		"00688M2",
	}, "\n")+"\n"), 0644)
	if err != nil {
		t.Fatalf("write plates.txt: %v", err)
	}

	store, err := targets.New(platesPath, pepper)
	if err != nil {
		t.Fatalf("targets.New: %v", err)
	}

	if store.Count() != 5 {
		t.Fatalf("expected 5 targets loaded, got %d", store.Count())
	}

	recorder := &testRecorder{}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/plates", handler.PlatesHandler(recorder, store, nil))
	mux.HandleFunc("/healthz", handler.HealthHandler(store))

	srv := httptest.NewServer(mux)
	defer srv.Close()

	t.Run("target plate matches", func(t *testing.T) {
		hash := clientHMAC("BRD1385", pepper)
		resp := postPlate(t, srv.URL, hash, 34.0, -118.0)

		if resp.Status != "ok" {
			t.Fatalf("expected status ok, got %s", resp.Status)
		}
		if !resp.Matched {
			t.Fatalf("expected matched=true for target plate BRD1385 (hash=%s)", hash)
		}
	})

	t.Run("non-target plate does not match", func(t *testing.T) {
		hash := clientHMAC("ZZZZZZZ", pepper)
		resp := postPlate(t, srv.URL, hash, 34.0, -118.0)

		if resp.Status != "ok" {
			t.Fatalf("expected status ok, got %s", resp.Status)
		}
		if resp.Matched {
			t.Fatalf("expected matched=false for non-target plate")
		}
	})

	t.Run("all plates in file are matchable", func(t *testing.T) {
		plates := []string{"ABC123", "BRD1385", "C23896C", "DMG837", "00688M2"}
		for _, plate := range plates {
			hash := clientHMAC(plate, pepper)
			resp := postPlate(t, srv.URL, hash, 0, 0)
			if !resp.Matched {
				t.Errorf("plate %s (hash=%s) should match but didn't", plate, hash)
			}
		}
	})

	t.Run("client normalization matches server normalization", func(t *testing.T) {
		variants := []string{"brd1385", "brd 1385", "BRD-1385", "  BRD1385  "}
		for _, v := range variants {
			hash := clientHMAC(v, pepper)
			resp := postPlate(t, srv.URL, hash, 0, 0)
			if !resp.Matched {
				t.Errorf("variant %q should normalize to BRD1385 and match, but didn't (hash=%s)", v, hash)
			}
		}
	})

	t.Run("healthz reports correct target count", func(t *testing.T) {
		resp, err := http.Get(srv.URL + "/healthz")
		if err != nil {
			t.Fatalf("GET /healthz: %v", err)
		}
		defer resp.Body.Close()

		var body map[string]interface{}
		if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
			t.Fatalf("failed to decode response: %v", err)
		}
		if body["targets_loaded"] != float64(5) {
			t.Fatalf("expected targets_loaded=5, got %v", body["targets_loaded"])
		}
	})

	t.Run("matched plates are recorded as sightings", func(t *testing.T) {
		recorder.mu.Lock()
		count := len(recorder.sightings)
		recorder.mu.Unlock()

		if count == 0 {
			t.Fatal("expected sightings to be recorded for matched plates")
		}
	})

	t.Run("non-matched plates are not recorded", func(t *testing.T) {
		recorder.mu.Lock()
		before := len(recorder.sightings)
		recorder.mu.Unlock()

		hash := clientHMAC("NONEXIST", pepper)
		postPlate(t, srv.URL, hash, 0, 0)

		recorder.mu.Lock()
		after := len(recorder.sightings)
		recorder.mu.Unlock()

		if after != before {
			t.Errorf("expected no new sightings for non-match, got %d new", after-before)
		}
	})
}

type plateResponse struct {
	Status  string `json:"status"`
	Matched bool   `json:"matched"`
}

func postPlate(t *testing.T, baseURL, hash string, lat, lng float64) plateResponse {
	t.Helper()
	body, _ := json.Marshal(map[string]interface{}{
		"plate_hash": hash,
		"latitude":   lat,
		"longitude":  lng,
	})
	resp, err := http.Post(baseURL+"/api/v1/plates", "application/json", strings.NewReader(string(body)))
	if err != nil {
		t.Fatalf("POST /api/v1/plates: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var pr plateResponse
	if err := json.NewDecoder(resp.Body).Decode(&pr); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	return pr
}
