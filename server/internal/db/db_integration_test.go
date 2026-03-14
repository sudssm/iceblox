//go:build integration

package db

import (
	"context"
	"os"
	"testing"
	"time"
)

func testDB(t *testing.T) *DB {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set, skipping integration test")
	}
	database, err := Connect(dsn)
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	t.Cleanup(func() { database.Close() })

	ctx := context.Background()
	if err := database.Migrate(ctx); err != nil {
		t.Fatalf("Migrate: %v", err)
	}

	pool := database.Pool()
	pool.ExecContext(ctx, "DELETE FROM sessions")
	pool.ExecContext(ctx, "DELETE FROM sightings")
	pool.ExecContext(ctx, "DELETE FROM device_tokens")
	pool.ExecContext(ctx, "DELETE FROM plates")

	return database
}

func TestMigrate_CreatesTablesIdempotently(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	if err := database.Migrate(ctx); err != nil {
		t.Fatalf("second Migrate should be idempotent: %v", err)
	}

	pool := database.Pool()
	var count int
	if err := pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM plates").Scan(&count); err != nil {
		t.Fatalf("plates table should exist: %v", err)
	}
	if err := pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM sightings").Scan(&count); err != nil {
		t.Fatalf("sightings table should exist: %v", err)
	}
}

func TestUpsertPlates_InsertsAndReturnsIDs(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	plates := []PlateRecord{
		{Plate: "ABC123", Hash: "aaaa" + "0000000000000000000000000000000000000000000000000000000000aa"},
		{Plate: "XYZ789", Hash: "bbbb" + "0000000000000000000000000000000000000000000000000000000000bb"},
	}

	mapping, err := database.UpsertPlates(ctx, plates)
	if err != nil {
		t.Fatalf("UpsertPlates: %v", err)
	}

	if len(mapping) != 2 {
		t.Fatalf("expected 2 mappings, got %d", len(mapping))
	}

	for _, p := range plates {
		id, ok := mapping[p.Hash]
		if !ok {
			t.Errorf("hash %s not found in mapping", p.Hash)
		}
		if id <= 0 {
			t.Errorf("expected positive plate_id for hash %s, got %d", p.Hash, id)
		}
	}
}

func TestUpsertPlates_UpdatesExistingPlate(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	hash := "cccc" + "0000000000000000000000000000000000000000000000000000000000cc"
	plates := []PlateRecord{{Plate: "OLD123", Hash: hash}}
	mapping1, err := database.UpsertPlates(ctx, plates)
	if err != nil {
		t.Fatalf("first UpsertPlates: %v", err)
	}
	id1 := mapping1[hash]

	plates[0].Plate = "NEW123"
	mapping2, err := database.UpsertPlates(ctx, plates)
	if err != nil {
		t.Fatalf("second UpsertPlates: %v", err)
	}
	id2 := mapping2[hash]

	if id1 != id2 {
		t.Errorf("expected same plate_id after upsert, got %d and %d", id1, id2)
	}

	pool := database.Pool()
	var plate string
	err = pool.QueryRowContext(ctx, "SELECT plate FROM plates WHERE hash = $1", hash).Scan(&plate)
	if err != nil {
		t.Fatalf("query plate: %v", err)
	}
	if plate != "NEW123" {
		t.Errorf("expected plate text 'NEW123', got %q", plate)
	}
}

func TestRecordSighting_InsertsSighting(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	hash := "dddd" + "0000000000000000000000000000000000000000000000000000000000dd"
	mapping, err := database.UpsertPlates(ctx, []PlateRecord{{Plate: "TEST1", Hash: hash}})
	if err != nil {
		t.Fatalf("UpsertPlates: %v", err)
	}
	plateID := mapping[hash]

	seenAt := time.Date(2026, 3, 8, 14, 30, 0, 0, time.UTC)
	sightingID, err := database.RecordSighting(ctx, plateID, seenAt, 34.0522, -118.2437, "device-abc", 0, 0)
	if err != nil {
		t.Fatalf("RecordSighting: %v", err)
	}
	if sightingID <= 0 {
		t.Errorf("expected positive sighting_id, got %d", sightingID)
	}

	pool := database.Pool()
	var (
		gotPlateID     int64
		gotSeenAt      time.Time
		gotLat, gotLng float64
		gotHardwareID  string
	)
	err = pool.QueryRowContext(ctx,
		"SELECT plate_id, seen_at, latitude, longitude, hardware_id FROM sightings WHERE plate_id = $1",
		plateID).Scan(&gotPlateID, &gotSeenAt, &gotLat, &gotLng, &gotHardwareID)
	if err != nil {
		t.Fatalf("query sighting: %v", err)
	}

	if gotPlateID != plateID {
		t.Errorf("plate_id: got %d, want %d", gotPlateID, plateID)
	}
	if !gotSeenAt.Equal(seenAt) {
		t.Errorf("seen_at: got %v, want %v", gotSeenAt, seenAt)
	}
	if gotLat != 34.0522 {
		t.Errorf("latitude: got %f, want 34.0522", gotLat)
	}
	if gotLng != -118.2437 {
		t.Errorf("longitude: got %f, want -118.2437", gotLng)
	}
	if gotHardwareID != "device-abc" {
		t.Errorf("hardware_id: got %q, want %q", gotHardwareID, "device-abc")
	}
}

func TestRecordSighting_MultipleSightingsPerPlate(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	hash := "eeee" + "0000000000000000000000000000000000000000000000000000000000ee"
	mapping, err := database.UpsertPlates(ctx, []PlateRecord{{Plate: "MULTI1", Hash: hash}})
	if err != nil {
		t.Fatalf("UpsertPlates: %v", err)
	}
	plateID := mapping[hash]

	for i := range 3 {
		seenAt := time.Date(2026, 3, 8, 10+i, 0, 0, 0, time.UTC)
		_, err = database.RecordSighting(ctx, plateID, seenAt, float64(30+i), float64(-100-i), "device-xyz", 0, 0)
		if err != nil {
			t.Fatalf("RecordSighting %d: %v", i, err)
		}
	}

	pool := database.Pool()
	var count int
	err = pool.QueryRowContext(ctx,
		"SELECT COUNT(*) FROM sightings WHERE plate_id = $1", plateID).Scan(&count)
	if err != nil {
		t.Fatalf("count sightings: %v", err)
	}
	if count != 3 {
		t.Errorf("expected 3 sightings, got %d", count)
	}
}

func TestRecordSighting_ForeignKeyConstraint(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	_, err := database.RecordSighting(ctx, 999999, time.Now(), 0, 0, "device-bad", 0, 0)
	if err == nil {
		t.Fatal("expected FK violation error for non-existent plate_id")
	}
}

func TestLoadPlateIDs_ReturnsAllPlates(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	plates := []PlateRecord{
		{Plate: "LOAD1", Hash: "ffff" + "0000000000000000000000000000000000000000000000000000000000f1"},
		{Plate: "LOAD2", Hash: "ffff" + "0000000000000000000000000000000000000000000000000000000000f2"},
		{Plate: "LOAD3", Hash: "ffff" + "0000000000000000000000000000000000000000000000000000000000f3"},
	}
	_, err := database.UpsertPlates(ctx, plates)
	if err != nil {
		t.Fatalf("UpsertPlates: %v", err)
	}

	mapping, err := database.LoadPlateIDs(ctx)
	if err != nil {
		t.Fatalf("LoadPlateIDs: %v", err)
	}

	if len(mapping) < 3 {
		t.Fatalf("expected at least 3 mappings, got %d", len(mapping))
	}

	for _, p := range plates {
		if _, ok := mapping[p.Hash]; !ok {
			t.Errorf("hash %s not found in LoadPlateIDs result", p.Hash)
		}
	}
}

func TestUpsertSession_CreatesAndIncrements(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	if err := database.UpsertSession(ctx, "sess-1", "device-a", 3); err != nil {
		t.Fatalf("first UpsertSession: %v", err)
	}

	pool := database.Pool()
	var vehicles, plates int
	var deviceID string
	if err := pool.QueryRowContext(ctx,
		"SELECT device_id, vehicles, plates FROM sessions WHERE session_id = $1", "sess-1").
		Scan(&deviceID, &vehicles, &plates); err != nil {
		t.Fatalf("query session after first upsert: %v", err)
	}

	if deviceID != "device-a" {
		t.Errorf("device_id: got %q, want %q", deviceID, "device-a")
	}
	if vehicles != 1 {
		t.Errorf("vehicles: got %d, want 1", vehicles)
	}
	if plates != 3 {
		t.Errorf("plates: got %d, want 3", plates)
	}

	if err := database.UpsertSession(ctx, "sess-1", "device-a", 5); err != nil {
		t.Fatalf("second UpsertSession: %v", err)
	}

	if err := pool.QueryRowContext(ctx,
		"SELECT vehicles, plates FROM sessions WHERE session_id = $1", "sess-1").
		Scan(&vehicles, &plates); err != nil {
		t.Fatalf("query session after second upsert: %v", err)
	}

	if vehicles != 2 {
		t.Errorf("vehicles after second upsert: got %d, want 2", vehicles)
	}
	if plates != 8 {
		t.Errorf("plates after second upsert: got %d, want 8", plates)
	}
}

func TestEndSession_SetsEndedAt(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	database.UpsertSession(ctx, "sess-end", "device-b", 1)

	if err := database.EndSession(ctx, "sess-end", 0.95, 42.5, 0.88, 35.2); err != nil {
		t.Fatalf("EndSession: %v", err)
	}

	pool := database.Pool()
	var endedAt *time.Time
	var maxDet, totalDet, maxOCR, totalOCR float64
	if err := pool.QueryRowContext(ctx,
		"SELECT ended_at, max_detection_confidence, total_detection_confidence, max_ocr_confidence, total_ocr_confidence FROM sessions WHERE session_id = $1", "sess-end").
		Scan(&endedAt, &maxDet, &totalDet, &maxOCR, &totalOCR); err != nil {
		t.Fatalf("query session after end: %v", err)
	}

	if endedAt == nil {
		t.Fatal("expected ended_at to be set")
	}
	if maxDet != 0.95 {
		t.Errorf("max_detection_confidence: got %f, want 0.95", maxDet)
	}
	if totalDet != 42.5 {
		t.Errorf("total_detection_confidence: got %f, want 42.5", totalDet)
	}
	if maxOCR != 0.88 {
		t.Errorf("max_ocr_confidence: got %f, want 0.88", maxOCR)
	}
	if totalOCR != 35.2 {
		t.Errorf("total_ocr_confidence: got %f, want 35.2", totalOCR)
	}
}

func TestEndSession_NoOpForMissingSession(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	if err := database.EndSession(ctx, "nonexistent-session", 0, 0, 0, 0); err != nil {
		t.Fatalf("EndSession for missing session should not error: %v", err)
	}
}
