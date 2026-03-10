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

type SentPush struct {
	ID            int64       `gorm:"primaryKey;autoIncrement"`
	DeviceTokenID int64       `gorm:"not null;index:idx_sent_pushes_device_token_id"`
	DeviceToken   DeviceToken `gorm:"foreignKey:DeviceTokenID;constraint:OnDelete:CASCADE"`
	PlateID       int64       `gorm:"not null"`
	Plate         Plate       `gorm:"foreignKey:PlateID;constraint:OnDelete:RESTRICT"`
	Latitude      float64     `gorm:"type:double precision;not null"`
	Longitude     float64     `gorm:"type:double precision;not null"`
	SentAt        time.Time   `gorm:"type:timestamptz;not null;index:idx_sent_pushes_sent_at"`
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
	return d.gorm.AutoMigrate(&Plate{}, &Sighting{}, &DeviceToken{}, &SentPush{})
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

func (d *DB) RecentPushesForDevice(ctx context.Context, deviceTokenID int64) ([]SentPush, error) {
	var pushes []SentPush
	if err := d.gorm.WithContext(ctx).Where("device_token_id = ?", deviceTokenID).Find(&pushes).Error; err != nil {
		return nil, fmt.Errorf("query sent_pushes: %w", err)
	}
	return pushes, nil
}

func (d *DB) RecordSentPush(ctx context.Context, deviceTokenID, plateID int64, lat, lng float64) error {
	sp := SentPush{
		DeviceTokenID: deviceTokenID,
		PlateID:       plateID,
		Latitude:      lat,
		Longitude:     lng,
		SentAt:        time.Now(),
	}
	return d.gorm.WithContext(ctx).Create(&sp).Error
}

func (d *DB) CleanupStalePushes(ctx context.Context, staleThreshold time.Duration) (int64, error) {
	cutoff := time.Now().Add(-staleThreshold)
	result := d.gorm.WithContext(ctx).
		Where("device_token_id IN (SELECT id FROM device_tokens WHERE updated_at < ?)", cutoff).
		Delete(&SentPush{})
	return result.RowsAffected, result.Error
}

func (d *DB) TouchDeviceToken(ctx context.Context, hardwareID string) error {
	return d.gorm.WithContext(ctx).
		Model(&DeviceToken{}).
		Where("hardware_id = ?", hardwareID).
		Update("updated_at", time.Now()).Error
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
