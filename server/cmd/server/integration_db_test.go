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
	"time"

	"iceblox/server/internal/db"
	"iceblox/server/internal/handler"
	"iceblox/server/internal/targets"
)

func TestRun_MigrateOnly_DoesNotRequirePepperOrPlates(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}

	env := map[string]string{
		"DATABASE_URL": dsn,
		"PLATES_FILE":  filepath.Join(t.TempDir(), "missing-plates.txt"),
	}

	if err := run(context.Background(), []string{"--migrate-only"}, func(key string) string {
		return env[key]
	}); err != nil {
		t.Fatalf("run migrate-only: %v", err)
	}

	database, err := db.Connect(dsn)
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer database.Close()

	var count int
	if err := database.Pool().QueryRowContext(context.Background(), `
		SELECT COUNT(*)
		FROM information_schema.tables
		WHERE table_schema = 'public'
		  AND table_name IN ('plates', 'sightings', 'device_tokens', 'sent_pushes', 'reports', 'sessions')
	`).Scan(&count); err != nil {
		t.Fatalf("query tables: %v", err)
	}
	if count != 6 {
		t.Fatalf("expected 6 migrated tables, got %d", count)
	}
}

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
	pool.ExecContext(ctx, "DELETE FROM sessions")
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
	mux.HandleFunc("/api/v1/plates", handler.PlatesHandler(database, store, nil, nil))
	srv := httptest.NewServer(mux)
	defer srv.Close()

	t.Run("matched plate creates sighting in database", func(t *testing.T) {
		hash := e2eHMAC("ICE001", pepper)
		body, _ := json.Marshal(map[string]interface{}{
			"plates": []map[string]interface{}{
				{
					"plate_hash": hash,
					"latitude":   40.7128,
					"longitude":  -74.0060,
					"timestamp":  "2026-03-08T10:00:00Z",
				},
			},
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
		results := result["results"].([]interface{})
		if results[0].(map[string]interface{})["matched"] != true {
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
			"plates": []map[string]interface{}{
				{
					"plate_hash": hash,
					"latitude":   40.0,
					"longitude":  -74.0,
				},
			},
		})

		resp, err := http.Post(srv.URL+"/api/v1/plates", "application/json", strings.NewReader(string(body)))
		if err != nil {
			t.Fatalf("POST: %v", err)
		}
		defer resp.Body.Close()

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		results := result["results"].([]interface{})
		if results[0].(map[string]interface{})["matched"] != false {
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
				"plates": []map[string]interface{}{
					{
						"plate_hash": hash,
						"latitude":   41.0 + float64(i),
						"longitude":  -73.0,
					},
				},
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
			"plates": []map[string]interface{}{
				{
					"plate_hash": hash,
					"latitude":   33.4484,
					"longitude":  -112.0740,
					"timestamp":  "2026-03-08T15:45:00Z",
				},
			},
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

func TestRecordSentPush(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}

	database, err := db.Connect(dsn)
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer database.Close()

	ctx := context.Background()
	database.Migrate(ctx)
	pool := database.Pool()
	pool.ExecContext(ctx, "DELETE FROM sent_pushes")
	pool.ExecContext(ctx, "DELETE FROM sightings")
	pool.ExecContext(ctx, "DELETE FROM device_tokens")
	pool.ExecContext(ctx, "DELETE FROM plates")

	pool.ExecContext(ctx, "INSERT INTO plates (plate, hash) VALUES ('TEST1', 'a000000000000000000000000000000000000000000000000000000000000001') ON CONFLICT DO NOTHING")
	var plateID int64
	pool.QueryRowContext(ctx, "SELECT id FROM plates WHERE hash = 'a000000000000000000000000000000000000000000000000000000000000001'").Scan(&plateID)

	database.UpsertDeviceToken(ctx, "hw-record", "tok-record", "ios")
	var dtID int64
	pool.QueryRowContext(ctx, "SELECT id FROM device_tokens WHERE hardware_id = 'hw-record'").Scan(&dtID)

	if err := database.RecordSentPush(ctx, dtID, plateID, 36.16, -86.78); err != nil {
		t.Fatalf("RecordSentPush: %v", err)
	}

	var count int
	pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM sent_pushes WHERE device_token_id = $1", dtID).Scan(&count)
	if count != 1 {
		t.Errorf("expected 1 sent_push, got %d", count)
	}
}

func TestRecentPushesForDevice(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}

	database, err := db.Connect(dsn)
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer database.Close()

	ctx := context.Background()
	database.Migrate(ctx)
	pool := database.Pool()
	pool.ExecContext(ctx, "DELETE FROM sent_pushes")
	pool.ExecContext(ctx, "DELETE FROM device_tokens")
	pool.ExecContext(ctx, "DELETE FROM plates")

	pool.ExecContext(ctx, "INSERT INTO plates (plate, hash) VALUES ('TEST2', 'b000000000000000000000000000000000000000000000000000000000000002') ON CONFLICT DO NOTHING")
	var plateID int64
	pool.QueryRowContext(ctx, "SELECT id FROM plates WHERE hash = 'b000000000000000000000000000000000000000000000000000000000000002'").Scan(&plateID)

	database.UpsertDeviceToken(ctx, "hw-recent", "tok-recent", "ios")
	var dtID int64
	pool.QueryRowContext(ctx, "SELECT id FROM device_tokens WHERE hardware_id = 'hw-recent'").Scan(&dtID)

	database.RecordSentPush(ctx, dtID, plateID, 36.16, -86.78)
	database.RecordSentPush(ctx, dtID, plateID, 37.0, -87.0)

	pushes, err := database.RecentPushesForDevice(ctx, dtID)
	if err != nil {
		t.Fatalf("RecentPushesForDevice: %v", err)
	}
	if len(pushes) != 2 {
		t.Errorf("expected 2 pushes, got %d", len(pushes))
	}
}

func TestCleanupStalePushes(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}

	database, err := db.Connect(dsn)
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer database.Close()

	ctx := context.Background()
	database.Migrate(ctx)
	pool := database.Pool()
	pool.ExecContext(ctx, "DELETE FROM sent_pushes")
	pool.ExecContext(ctx, "DELETE FROM device_tokens")
	pool.ExecContext(ctx, "DELETE FROM plates")

	pool.ExecContext(ctx, "INSERT INTO plates (plate, hash) VALUES ('TEST3', 'c000000000000000000000000000000000000000000000000000000000000003') ON CONFLICT DO NOTHING")
	var plateID int64
	pool.QueryRowContext(ctx, "SELECT id FROM plates WHERE hash = 'c000000000000000000000000000000000000000000000000000000000000003'").Scan(&plateID)

	// Create a "stale" device token with old updated_at
	database.UpsertDeviceToken(ctx, "hw-stale", "tok-stale", "ios")
	pool.ExecContext(ctx, "UPDATE device_tokens SET updated_at = NOW() - INTERVAL '2 hours' WHERE hardware_id = 'hw-stale'")
	var staleID int64
	pool.QueryRowContext(ctx, "SELECT id FROM device_tokens WHERE hardware_id = 'hw-stale'").Scan(&staleID)

	// Create a "fresh" device token
	database.UpsertDeviceToken(ctx, "hw-fresh", "tok-fresh", "ios")
	var freshID int64
	pool.QueryRowContext(ctx, "SELECT id FROM device_tokens WHERE hardware_id = 'hw-fresh'").Scan(&freshID)

	database.RecordSentPush(ctx, staleID, plateID, 36.0, -86.0)
	database.RecordSentPush(ctx, freshID, plateID, 37.0, -87.0)

	deleted, err := database.CleanupStalePushes(ctx, 30*time.Minute)
	if err != nil {
		t.Fatalf("CleanupStalePushes: %v", err)
	}
	if deleted != 1 {
		t.Errorf("expected 1 deleted, got %d", deleted)
	}

	var remaining int
	pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM sent_pushes").Scan(&remaining)
	if remaining != 1 {
		t.Errorf("expected 1 remaining push, got %d", remaining)
	}
}

func TestTouchDeviceToken(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}

	database, err := db.Connect(dsn)
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer database.Close()

	ctx := context.Background()
	database.Migrate(ctx)
	pool := database.Pool()
	pool.ExecContext(ctx, "DELETE FROM sent_pushes")
	pool.ExecContext(ctx, "DELETE FROM device_tokens")

	database.UpsertDeviceToken(ctx, "hw-touch", "tok-touch", "ios")
	pool.ExecContext(ctx, "UPDATE device_tokens SET updated_at = NOW() - INTERVAL '1 hour' WHERE hardware_id = 'hw-touch'")

	var before time.Time
	pool.QueryRowContext(ctx, "SELECT updated_at FROM device_tokens WHERE hardware_id = 'hw-touch'").Scan(&before)

	if err := database.TouchDeviceToken(ctx, "hw-touch"); err != nil {
		t.Fatalf("TouchDeviceToken: %v", err)
	}

	var after time.Time
	pool.QueryRowContext(ctx, "SELECT updated_at FROM device_tokens WHERE hardware_id = 'hw-touch'").Scan(&after)

	if !after.After(before) {
		t.Errorf("expected updated_at to be refreshed, before=%v after=%v", before, after)
	}
}

func TestSentPush_CascadeDelete(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}

	database, err := db.Connect(dsn)
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer database.Close()

	ctx := context.Background()
	database.Migrate(ctx)
	pool := database.Pool()
	pool.ExecContext(ctx, "DELETE FROM sent_pushes")
	pool.ExecContext(ctx, "DELETE FROM device_tokens")
	pool.ExecContext(ctx, "DELETE FROM plates")

	pool.ExecContext(ctx, "INSERT INTO plates (plate, hash) VALUES ('TEST4', 'd000000000000000000000000000000000000000000000000000000000000004') ON CONFLICT DO NOTHING")
	var plateID int64
	pool.QueryRowContext(ctx, "SELECT id FROM plates WHERE hash = 'd000000000000000000000000000000000000000000000000000000000000004'").Scan(&plateID)

	database.UpsertDeviceToken(ctx, "hw-cascade", "tok-cascade", "ios")
	var dtID int64
	pool.QueryRowContext(ctx, "SELECT id FROM device_tokens WHERE hardware_id = 'hw-cascade'").Scan(&dtID)

	database.RecordSentPush(ctx, dtID, plateID, 36.0, -86.0)

	var countBefore int
	pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM sent_pushes WHERE device_token_id = $1", dtID).Scan(&countBefore)
	if countBefore != 1 {
		t.Fatalf("expected 1 sent_push before delete, got %d", countBefore)
	}

	database.DeleteDeviceToken(ctx, dtID)

	var countAfter int
	pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM sent_pushes WHERE device_token_id = $1", dtID).Scan(&countAfter)
	if countAfter != 0 {
		t.Errorf("expected 0 sent_pushes after cascade delete, got %d", countAfter)
	}
}

func TestEndToEnd_SessionTracking(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}

	pepper := []byte("e2e-session-pepper")
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
	pool.ExecContext(ctx, "DELETE FROM sessions")
	pool.ExecContext(ctx, "DELETE FROM sightings")
	pool.ExecContext(ctx, "DELETE FROM plates")

	dir := t.TempDir()
	platesPath := filepath.Join(dir, "plates.txt")
	os.WriteFile(platesPath, []byte("SESS001\n"), 0644)

	store, err := targets.New(platesPath, pepper)
	if err != nil {
		t.Fatalf("targets.New: %v", err)
	}
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
	mux.HandleFunc("/api/v1/plates", handler.PlatesHandler(database, store, nil, database))
	mux.HandleFunc("/api/v1/sessions/end", handler.EndSessionHandler(database))
	srv := httptest.NewServer(mux)
	defer srv.Close()

	sessionID := "e2e-sess-001"

	t.Run("upload with session_id creates session", func(t *testing.T) {
		hash := e2eHMAC("SESS001", pepper)
		body, _ := json.Marshal(map[string]interface{}{
			"session_id": sessionID,
			"plates": []map[string]interface{}{
				{"plate_hash": hash, "latitude": 40.0, "longitude": -74.0},
			},
		})

		req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/v1/plates", strings.NewReader(string(body)))
		req.Header.Set("X-Device-ID", "e2e-sess-device")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("POST: %v", err)
		}
		resp.Body.Close()

		var vehicles, plates int
		if err := pool.QueryRowContext(ctx,
			"SELECT vehicles, plates FROM sessions WHERE session_id = $1", sessionID).
			Scan(&vehicles, &plates); err != nil {
			t.Fatalf("query session: %v", err)
		}
		if vehicles != 1 {
			t.Errorf("expected vehicles=1, got %d", vehicles)
		}
		if plates != 1 {
			t.Errorf("expected plates=1, got %d", plates)
		}
	})

	t.Run("second upload increments session counters", func(t *testing.T) {
		hash := e2eHMAC("SESS001", pepper)
		body, _ := json.Marshal(map[string]interface{}{
			"session_id": sessionID,
			"plates": []map[string]interface{}{
				{"plate_hash": hash, "latitude": 41.0, "longitude": -74.0},
			},
		})

		req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/v1/plates", strings.NewReader(string(body)))
		req.Header.Set("X-Device-ID", "e2e-sess-device")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("POST: %v", err)
		}
		resp.Body.Close()

		var vehicles, plates int
		if err := pool.QueryRowContext(ctx,
			"SELECT vehicles, plates FROM sessions WHERE session_id = $1", sessionID).
			Scan(&vehicles, &plates); err != nil {
			t.Fatalf("query session: %v", err)
		}
		if vehicles != 2 {
			t.Errorf("expected vehicles=2, got %d", vehicles)
		}
		if plates != 2 {
			t.Errorf("expected plates=2, got %d", plates)
		}
	})

	t.Run("end session sets ended_at and confidence stats", func(t *testing.T) {
		body, _ := json.Marshal(map[string]interface{}{
			"session_id":                 sessionID,
			"max_detection_confidence":   0.95,
			"total_detection_confidence": 1.8,
			"max_ocr_confidence":         0.88,
			"total_ocr_confidence":       1.6,
		})
		resp, err := http.Post(srv.URL+"/api/v1/sessions/end", "application/json", strings.NewReader(string(body)))
		if err != nil {
			t.Fatalf("POST sessions/end: %v", err)
		}
		resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200, got %d", resp.StatusCode)
		}

		var endedAt *time.Time
		var maxDet, totalDet, maxOCR, totalOCR float64
		if err := pool.QueryRowContext(ctx,
			"SELECT ended_at, max_detection_confidence, total_detection_confidence, max_ocr_confidence, total_ocr_confidence FROM sessions WHERE session_id = $1", sessionID).
			Scan(&endedAt, &maxDet, &totalDet, &maxOCR, &totalOCR); err != nil {
			t.Fatalf("query session: %v", err)
		}
		if endedAt == nil {
			t.Fatal("expected ended_at to be set after ending session")
		}
		if maxDet != 0.95 {
			t.Errorf("max_detection_confidence: got %f, want 0.95", maxDet)
		}
		if totalDet != 1.8 {
			t.Errorf("total_detection_confidence: got %f, want 1.8", totalDet)
		}
		if maxOCR != 0.88 {
			t.Errorf("max_ocr_confidence: got %f, want 0.88", maxOCR)
		}
		if totalOCR != 1.6 {
			t.Errorf("total_ocr_confidence: got %f, want 1.6", totalOCR)
		}
	})

	t.Run("upload without session_id creates no session", func(t *testing.T) {
		var countBefore int
		if err := pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM sessions").Scan(&countBefore); err != nil {
			t.Fatalf("query session count: %v", err)
		}

		hash := e2eHMAC("SESS001", pepper)
		body, _ := json.Marshal(map[string]interface{}{
			"plates": []map[string]interface{}{
				{"plate_hash": hash, "latitude": 42.0, "longitude": -74.0},
			},
		})
		resp, err := http.Post(srv.URL+"/api/v1/plates", "application/json", strings.NewReader(string(body)))
		if err != nil {
			t.Fatalf("POST: %v", err)
		}
		resp.Body.Close()

		var countAfter int
		if err := pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM sessions").Scan(&countAfter); err != nil {
			t.Fatalf("query session count: %v", err)
		}
		if countAfter != countBefore {
			t.Errorf("expected no new sessions, got %d new", countAfter-countBefore)
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
