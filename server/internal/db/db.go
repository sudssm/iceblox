package db

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"gorm.io/gorm/logger"
)

type DB struct {
	gorm *gorm.DB
}

type Plate struct {
	ID    int64  `gorm:"primaryKey;autoIncrement"`
	Plate string `gorm:"type:text;not null"`
	Hash  string `gorm:"type:varchar(64);not null;uniqueIndex"`
}

type Sighting struct {
	ID            int64     `gorm:"primaryKey;autoIncrement"`
	PlateID       int64     `gorm:"not null;index:idx_sightings_plate_id"`
	Plate         Plate     `gorm:"foreignKey:PlateID;constraint:OnDelete:RESTRICT"`
	SeenAt        time.Time `gorm:"type:timestamptz;not null;index:idx_sightings_seen_at"`
	Latitude      float64   `gorm:"type:double precision;not null;index:idx_sightings_location,composite:location"`
	Longitude     float64   `gorm:"type:double precision;not null;index:idx_sightings_location,composite:location"`
	HardwareID    string    `gorm:"type:text;not null"`
	Substitutions int       `gorm:"not null;default:0"`
}

type DeviceToken struct {
	ID         int64     `gorm:"primaryKey;autoIncrement"`
	HardwareID string    `gorm:"type:text;not null;uniqueIndex:idx_device_tokens_hw_platform"`
	Token      string    `gorm:"type:text;not null"`
	Platform   string    `gorm:"type:text;not null;uniqueIndex:idx_device_tokens_hw_platform;check:platform IN ('ios','android')"`
	UpdatedAt  time.Time `gorm:"type:timestamptz;not null;autoUpdateTime"`
}

// PlateRecord is the input type for UpsertPlates (no ID needed).
type PlateRecord struct {
	Plate string
	Hash  string
}

// SightingResult is a denormalized sighting joined with its plate text.
type SightingResult struct {
	ID            int64
	PlateID       int64
	Plate         string
	SeenAt        time.Time
	Latitude      float64
	Longitude     float64
	HardwareID    string
	Substitutions int
}

func Connect(dsn string) (*DB, error) {
	gormDB, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	sqlDB, err := gormDB.DB()
	if err != nil {
		return nil, fmt.Errorf("get underlying sql.DB: %w", err)
	}
	sqlDB.SetMaxOpenConns(25)
	sqlDB.SetMaxIdleConns(5)
	sqlDB.SetConnMaxLifetime(5 * time.Minute)

	if err := sqlDB.PingContext(context.Background()); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}

	return &DB{gorm: gormDB}, nil
}

func (d *DB) Migrate(_ context.Context) error {
	return d.gorm.AutoMigrate(&Plate{}, &Sighting{}, &DeviceToken{})
}

func (d *DB) UpsertPlates(ctx context.Context, plates []PlateRecord) (map[string]int64, error) {
	if len(plates) == 0 {
		return d.LoadPlateIDs(ctx)
	}

	records := make([]Plate, len(plates))
	for i, p := range plates {
		records[i] = Plate{Plate: p.Plate, Hash: p.Hash}
	}

	result := d.gorm.WithContext(ctx).
		Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "hash"}},
			DoUpdates: clause.AssignmentColumns([]string{"plate"}),
		}).
		Create(&records)
	if result.Error != nil {
		return nil, fmt.Errorf("upsert plates: %w", result.Error)
	}

	return d.LoadPlateIDs(ctx)
}

func (d *DB) LoadPlateIDs(ctx context.Context) (map[string]int64, error) {
	var plates []Plate
	if err := d.gorm.WithContext(ctx).Select("id", "hash").Find(&plates).Error; err != nil {
		return nil, fmt.Errorf("query plates: %w", err)
	}
	mapping := make(map[string]int64, len(plates))
	for _, p := range plates {
		mapping[p.Hash] = p.ID
	}
	return mapping, nil
}

func (d *DB) RecordSighting(ctx context.Context, plateID int64, seenAt time.Time, lat, lng float64, hardwareID string, substitutions int) (int64, error) {
	s := Sighting{
		PlateID:       plateID,
		SeenAt:        seenAt,
		Latitude:      lat,
		Longitude:     lng,
		HardwareID:    hardwareID,
		Substitutions: substitutions,
	}
	if err := d.gorm.WithContext(ctx).Create(&s).Error; err != nil {
		return 0, fmt.Errorf("insert sighting: %w", err)
	}
	return s.ID, nil
}

func (d *DB) UpsertDeviceToken(ctx context.Context, hardwareID, token, platform string) error {
	dt := DeviceToken{
		HardwareID: hardwareID,
		Token:      token,
		Platform:   platform,
		UpdatedAt:  time.Now(),
	}
	return d.gorm.WithContext(ctx).
		Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "hardware_id"}, {Name: "platform"}},
			DoUpdates: clause.AssignmentColumns([]string{"token", "updated_at"}),
		}).
		Create(&dt).Error
}

func (d *DB) AllDeviceTokens(ctx context.Context) ([]DeviceToken, error) {
	var tokens []DeviceToken
	if err := d.gorm.WithContext(ctx).Find(&tokens).Error; err != nil {
		return nil, fmt.Errorf("query device_tokens: %w", err)
	}
	return tokens, nil
}

func (d *DB) DeleteDeviceToken(ctx context.Context, id int64) error {
	return d.gorm.WithContext(ctx).Delete(&DeviceToken{}, id).Error
}

// RecentSightings returns sightings within a bounding box since the given time,
// joined with plate text.
func (d *DB) RecentSightings(ctx context.Context, minLat, maxLat, minLng, maxLng float64, since time.Time) ([]SightingResult, error) {
	var results []SightingResult
	err := d.gorm.WithContext(ctx).
		Table("sightings s").
		Select("s.id, s.plate_id, p.plate, s.seen_at, s.latitude, s.longitude, s.hardware_id, s.substitutions").
		Joins("JOIN plates p ON p.id = s.plate_id").
		Where("s.seen_at >= ? AND s.latitude BETWEEN ? AND ? AND s.longitude BETWEEN ? AND ?",
			since, minLat, maxLat, minLng, maxLng).
		Order("s.seen_at DESC").
		Scan(&results).Error
	if err != nil {
		return nil, fmt.Errorf("query recent sightings: %w", err)
	}
	return results, nil
}

// Pool returns the underlying *sql.DB for direct queries (e.g., in tests).
// Panics if the underlying connection pool is unavailable.
func (d *DB) Pool() *sql.DB {
	sqlDB, err := d.gorm.DB()
	if err != nil {
		panic(fmt.Sprintf("gorm.DB(): %v", err))
	}
	return sqlDB
}

func (d *DB) Close() error {
	sqlDB, err := d.gorm.DB()
	if err != nil {
		return err
	}
	return sqlDB.Close()
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
	hardware_id TEXT NOT NULL,
	substitutions INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS device_tokens (
	id SERIAL PRIMARY KEY,
	hardware_id TEXT NOT NULL,
	token TEXT NOT NULL,
	platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	UNIQUE(hardware_id, platform)
);

CREATE INDEX IF NOT EXISTS idx_sightings_plate_id ON sightings(plate_id);
CREATE INDEX IF NOT EXISTS idx_sightings_seen_at ON sightings(seen_at);
CREATE INDEX IF NOT EXISTS idx_sightings_location ON sightings(latitude, longitude);

-- migrations
ALTER TABLE sightings ADD COLUMN IF NOT EXISTS substitutions INTEGER NOT NULL DEFAULT 0;
`
