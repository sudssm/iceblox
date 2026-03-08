//go:build integration

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
	"testing"

	"cameras/server/internal/db"
	"cameras/server/internal/handler"
	"cameras/server/internal/targets"
)

func TestEndToEnd_WithDatabase(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}

	pepper := []byte("e2e-db-test-pepper")
	ctx := context.Background()

	database, err := db.Connect(dsn)
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer database.Close()

	if err := database.Migrate(ctx); err != nil {
		t.Fatalf("Migrate: %v", err)
	}

	pool := database.Pool()
	pool.ExecContext(ctx, "DELETE FROM sightings")
	pool.ExecContext(ctx, "DELETE FROM plates")

	// Create plates file
	dir := t.TempDir()
	platesPath := filepath.Join(dir, "plates.txt")
	os.WriteFile(platesPath, []byte("ICE001\nICE002\nICE003\n"), 0644)

	store, err := targets.New(platesPath, pepper)
	if err != nil {
		t.Fatalf("targets.New: %v", err)
	}

	// Seed DB
	records := store.Records()
	dbRecords := make([]db.PlateRecord, len(records))
	for i, r := range records {
		dbRecords[i] = db.PlateRecord{Plate: r.Plate, Hash: r.Hash}
	}
	mapping, err := database.UpsertPlates(ctx, dbRecords)
	if err != nil {
		t.Fatalf("UpsertPlates: %v", err)
	}
	store.SetPlateIDs(mapping)

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/plates", handler.PlatesHandler(database, store))
	srv := httptest.NewServer(mux)
	defer srv.Close()

	t.Run("matched plate creates sighting in database", func(t *testing.T) {
		hash := e2eHMAC("ICE001", pepper)
		body, _ := json.Marshal(map[string]interface{}{
			"plate_hash": hash,
			"latitude":   40.7128,
			"longitude":  -74.0060,
			"timestamp":  "2026-03-08T10:00:00Z",
		})

		req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/v1/plates", strings.NewReader(string(body)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Device-ID", "e2e-device-001")

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("POST: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200, got %d", resp.StatusCode)
		}

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		if result["matched"] != true {
			t.Fatal("expected matched=true")
		}

		var count int
		pool.QueryRowContext(ctx,
			"SELECT COUNT(*) FROM sightings WHERE hardware_id = $1", "e2e-device-001").Scan(&count)
		if count != 1 {
			t.Errorf("expected 1 sighting in DB, got %d", count)
		}
	})

	t.Run("non-matched plate creates no sighting", func(t *testing.T) {
		hash := e2eHMAC("NOTARGET", pepper)
		body, _ := json.Marshal(map[string]interface{}{
			"plate_hash": hash,
			"latitude":   40.0,
			"longitude":  -74.0,
		})

		resp, err := http.Post(srv.URL+"/api/v1/plates", "application/json", strings.NewReader(string(body)))
		if err != nil {
			t.Fatalf("POST: %v", err)
		}
		defer resp.Body.Close()

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		if result["matched"] != false {
			t.Fatal("expected matched=false")
		}

		var count int
		pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM sightings").Scan(&count)
		if count != 1 {
			t.Errorf("expected still 1 total sighting (no new ones), got %d", count)
		}
	})

	t.Run("multiple sightings for same plate accumulate", func(t *testing.T) {
		hash := e2eHMAC("ICE002", pepper)
		for i := range 3 {
			body, _ := json.Marshal(map[string]interface{}{
				"plate_hash": hash,
				"latitude":   41.0 + float64(i),
				"longitude":  -73.0,
			})
			req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/v1/plates", strings.NewReader(string(body)))
			req.Header.Set("X-Device-ID", "e2e-device-002")
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("POST %d: %v", i, err)
			}
			resp.Body.Close()
		}

		plateID, _ := store.PlateID(hash)
		var count int
		pool.QueryRowContext(ctx,
			"SELECT COUNT(*) FROM sightings WHERE plate_id = $1", plateID).Scan(&count)
		if count != 3 {
			t.Errorf("expected 3 sightings for ICE002, got %d", count)
		}
	})

	t.Run("sighting stores correct GPS and hardware_id", func(t *testing.T) {
		hash := e2eHMAC("ICE003", pepper)
		body, _ := json.Marshal(map[string]interface{}{
			"plate_hash": hash,
			"latitude":   33.4484,
			"longitude":  -112.0740,
			"timestamp":  "2026-03-08T15:45:00Z",
		})

		req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/v1/plates", strings.NewReader(string(body)))
		req.Header.Set("X-Device-ID", "phoenix-unit-7")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("POST: %v", err)
		}
		resp.Body.Close()

		plateID, _ := store.PlateID(hash)
		var lat, lng float64
		var hwID string
		pool.QueryRowContext(ctx,
			"SELECT latitude, longitude, hardware_id FROM sightings WHERE plate_id = $1",
			plateID).Scan(&lat, &lng, &hwID)
		if lat != 33.4484 {
			t.Errorf("latitude: got %f, want 33.4484", lat)
		}
		if lng != -112.0740 {
			t.Errorf("longitude: got %f, want -112.0740", lng)
		}
		if hwID != "phoenix-unit-7" {
			t.Errorf("hardware_id: got %q, want %q", hwID, "phoenix-unit-7")
		}
	})
}

func e2eHMAC(plate string, pepper []byte) string {
	plate = strings.ToUpper(plate)
	plate = strings.ReplaceAll(plate, " ", "")
	plate = strings.ReplaceAll(plate, "-", "")
	mac := hmac.New(sha256.New, pepper)
	mac.Write([]byte(plate))
	return hex.EncodeToString(mac.Sum(nil))
}
