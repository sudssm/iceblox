package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"cameras/server/internal/handler"
	"cameras/server/internal/targets"
)

// clientHMAC computes HMAC-SHA256 the same way a mobile client would,
// independent of the server's implementation.
func clientHMAC(plate string, pepper []byte) string {
	plate = strings.ToUpper(plate)
	plate = strings.ReplaceAll(plate, " ", "")
	plate = strings.ReplaceAll(plate, "-", "")
	mac := hmac.New(sha256.New, pepper)
	mac.Write([]byte(plate))
	return hex.EncodeToString(mac.Sum(nil))
}

func TestEndToEnd_PlatesFileToAPIMatch(t *testing.T) {
	pepper := []byte("integration-test-pepper")

	// Simulate plates.txt as it would come from `make extract`
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

	logPath := filepath.Join(dir, "test.jsonl")
	logger, err := handler.NewJSONLLogger(logPath)
	if err != nil {
		t.Fatalf("NewJSONLLogger: %v", err)
	}
	defer logger.Close()

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/plates", handler.PlatesHandler(logger, store))
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
		// A client scanning "brd 1385" or "brd-1385" should match "BRD1385" in the file
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
		json.NewDecoder(resp.Body).Decode(&body)
		if body["targets_loaded"] != float64(5) {
			t.Fatalf("expected targets_loaded=5, got %v", body["targets_loaded"])
		}
	})

	t.Run("matches are logged to JSONL", func(t *testing.T) {
		logger.Close()
		data, err := os.ReadFile(logPath)
		if err != nil {
			t.Fatalf("read log: %v", err)
		}
		lines := strings.Split(strings.TrimSpace(string(data)), "\n")
		if len(lines) == 0 {
			t.Fatal("expected log entries")
		}

		var foundMatch, foundNonMatch bool
		for _, line := range lines {
			var entry map[string]interface{}
			json.Unmarshal([]byte(line), &entry)
			if matched, ok := entry["matched"].(bool); ok {
				if matched {
					foundMatch = true
				} else {
					foundNonMatch = true
				}
			}
		}
		if !foundMatch {
			t.Error("expected at least one matched=true log entry")
		}
		if !foundNonMatch {
			t.Error("expected at least one matched=false log entry")
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
	json.NewDecoder(resp.Body).Decode(&pr)
	return pr
}
