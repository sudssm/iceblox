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

	// Clean tables before each test
	database.pool.ExecContext(ctx, "DELETE FROM sightings")
	database.pool.ExecContext(ctx, "DELETE FROM plates")

	return database
}

func TestMigrate_CreatesTablesIdempotently(t *testing.T) {
	database := testDB(t)
	ctx := context.Background()

	// Running migrate again should not error
	if err := database.Migrate(ctx); err != nil {
		t.Fatalf("second Migrate should be idempotent: %v", err)
	}

	// Verify tables exist by querying them
	var count int
	if err := database.pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM plates").Scan(&count); err != nil {
		t.Fatalf("plates table should exist: %v", err)
	}
	if err := database.pool.QueryRowContext(ctx, "SELECT COUNT(*) FROM sightings").Scan(&count); err != nil {
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

	// Upsert again with updated plate text
	plates[0].Plate = "NEW123"
	mapping2, err := database.UpsertPlates(ctx, plates)
	if err != nil {
		t.Fatalf("second UpsertPlates: %v", err)
	}
	id2 := mapping2[hash]

	if id1 != id2 {
		t.Errorf("expected same plate_id after upsert, got %d and %d", id1, id2)
	}

	// Verify plate text was updated
	var plate string
	err = database.pool.QueryRowContext(ctx, "SELECT plate FROM plates WHERE hash = $1", hash).Scan(&plate)
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
	err = database.RecordSighting(ctx, plateID, seenAt, 34.0522, -118.2437, "device-abc")
	if err != nil {
		t.Fatalf("RecordSighting: %v", err)
	}

	var (
		gotPlateID    int64
		gotSeenAt     time.Time
		gotLat, gotLng float64
		gotHardwareID string
	)
	err = database.pool.QueryRowContext(ctx,
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
		err = database.RecordSighting(ctx, plateID, seenAt, float64(30+i), float64(-100-i), "device-xyz")
		if err != nil {
			t.Fatalf("RecordSighting %d: %v", i, err)
		}
	}

	var count int
	err = database.pool.QueryRowContext(ctx,
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

	err := database.RecordSighting(ctx, 999999, time.Now(), 0, 0, "device-bad")
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
