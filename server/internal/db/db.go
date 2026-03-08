package db

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type DB struct {
	pool *sql.DB
}

type PlateRecord struct {
	Plate string
	Hash  string
}

type DeviceToken struct {
	ID         int64
	HardwareID string
	Token      string
	Platform   string
	UpdatedAt  time.Time
}

func Connect(dsn string) (*DB, error) {
	pool, err := sql.Open("pgx", dsn)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	pool.SetMaxOpenConns(25)
	pool.SetMaxIdleConns(5)
	pool.SetConnMaxLifetime(5 * time.Minute)
	if err := pool.PingContext(context.Background()); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}
	return &DB{pool: pool}, nil
}

func (d *DB) Migrate(ctx context.Context) error {
	_, err := d.pool.ExecContext(ctx, schema)
	return err
}

func (d *DB) UpsertPlates(ctx context.Context, plates []PlateRecord) (map[string]int64, error) {
	tx, err := d.pool.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(ctx,
		`INSERT INTO plates (plate, hash) VALUES ($1, $2)
		 ON CONFLICT (hash) DO UPDATE SET plate = EXCLUDED.plate`)
	if err != nil {
		return nil, fmt.Errorf("prepare upsert: %w", err)
	}
	defer stmt.Close()

	for _, p := range plates {
		if _, err := stmt.ExecContext(ctx, p.Plate, p.Hash); err != nil {
			return nil, fmt.Errorf("upsert plate %s: %w", p.Plate, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}

	return d.LoadPlateIDs(ctx)
}

func (d *DB) LoadPlateIDs(ctx context.Context) (map[string]int64, error) {
	rows, err := d.pool.QueryContext(ctx, `SELECT id, hash FROM plates`)
	if err != nil {
		return nil, fmt.Errorf("query plates: %w", err)
	}
	defer rows.Close()

	mapping := make(map[string]int64)
	for rows.Next() {
		var id int64
		var hash string
		if err := rows.Scan(&id, &hash); err != nil {
			return nil, fmt.Errorf("scan plate: %w", err)
		}
		mapping[hash] = id
	}
	return mapping, rows.Err()
}

func (d *DB) RecordSighting(ctx context.Context, plateID int64, seenAt time.Time, lat, lng float64, hardwareID string) (int64, error) {
	var id int64
	err := d.pool.QueryRowContext(ctx,
		`INSERT INTO sightings (plate_id, seen_at, latitude, longitude, hardware_id)
		 VALUES ($1, $2, $3, $4, $5) RETURNING id`,
		plateID, seenAt, lat, lng, hardwareID).Scan(&id)
	return id, err
}

func (d *DB) UpsertDeviceToken(ctx context.Context, hardwareID, token, platform string) error {
	_, err := d.pool.ExecContext(ctx,
		`INSERT INTO device_tokens (hardware_id, token, platform, updated_at)
		 VALUES ($1, $2, $3, NOW())
		 ON CONFLICT (hardware_id, platform) DO UPDATE
		 SET token = EXCLUDED.token, updated_at = NOW()`,
		hardwareID, token, platform)
	return err
}

func (d *DB) AllDeviceTokens(ctx context.Context) ([]DeviceToken, error) {
	rows, err := d.pool.QueryContext(ctx,
		`SELECT id, hardware_id, token, platform, updated_at FROM device_tokens`)
	if err != nil {
		return nil, fmt.Errorf("query device_tokens: %w", err)
	}
	defer rows.Close()

	var tokens []DeviceToken
	for rows.Next() {
		var dt DeviceToken
		if err := rows.Scan(&dt.ID, &dt.HardwareID, &dt.Token, &dt.Platform, &dt.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan device_token: %w", err)
		}
		tokens = append(tokens, dt)
	}
	return tokens, rows.Err()
}

func (d *DB) DeleteDeviceToken(ctx context.Context, id int64) error {
	_, err := d.pool.ExecContext(ctx, `DELETE FROM device_tokens WHERE id = $1`, id)
	return err
}

// Pool returns the underlying *sql.DB for direct queries (e.g., in tests).
func (d *DB) Pool() *sql.DB {
	return d.pool
}

func (d *DB) Close() error {
	return d.pool.Close()
}

const schema = `
CREATE TABLE IF NOT EXISTS plates (
	id SERIAL PRIMARY KEY,
	plate TEXT NOT NULL,
	hash VARCHAR(64) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS sightings (
	id SERIAL PRIMARY KEY,
	plate_id INTEGER NOT NULL REFERENCES plates(id),
	seen_at TIMESTAMPTZ NOT NULL,
	latitude DOUBLE PRECISION NOT NULL,
	longitude DOUBLE PRECISION NOT NULL,
	hardware_id TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sightings_plate_id ON sightings(plate_id);
CREATE INDEX IF NOT EXISTS idx_sightings_seen_at ON sightings(seen_at);

CREATE TABLE IF NOT EXISTS device_tokens (
	id          SERIAL PRIMARY KEY,
	hardware_id TEXT NOT NULL,
	token       TEXT NOT NULL,
	platform    TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
	updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	UNIQUE(hardware_id, platform)
);
`
