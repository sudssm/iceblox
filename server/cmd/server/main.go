package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"iceblox/server/internal/db"
	"iceblox/server/internal/handler"
	"iceblox/server/internal/push"
	"iceblox/server/internal/stopice"
	"iceblox/server/internal/storage"
	"iceblox/server/internal/subscribers"
	"iceblox/server/internal/targets"
)

func main() {
	if err := run(context.Background(), os.Args[1:], os.Getenv); err != nil {
		log.Fatal(err)
	}
}

func run(ctx context.Context, args []string, getenv func(string) string) error {
	fs := flag.NewFlagSet("server", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	port := fs.Int("port", 8080, "server listen port")
	platesFile := fs.String("plates-file", "data/plates.txt", "path to plaintext plates file")
	pepper := fs.String("pepper", "", "HMAC pepper for hashing plates")
	apnsKeyFile := fs.String("apns-key-file", "", "path to APNs .p8 key file")
	apnsKeyID := fs.String("apns-key-id", "", "APNs key ID")
	apnsTeamID := fs.String("apns-team-id", "", "APNs team ID")
	apnsBundleID := fs.String("apns-bundle-id", "", "APNs bundle ID")
	apnsProduction := fs.Bool("apns-production", false, "use APNs production endpoint")
	fcmServiceAccount := fs.String("fcm-service-account", "", "path to FCM service account JSON file")
	dbDSN := fs.String("db-dsn", "postgres://postgres:iceblox@localhost:5432/iceblox?sslmode=disable", "PostgreSQL connection string")
	reportUploadDir := fs.String("report-upload-dir", "data/reports", "directory for report photo uploads")
	migrateOnly := fs.Bool("migrate-only", false, "run database migrations and exit")
	s3Bucket := fs.String("s3-bucket", "", "S3 bucket for report photos")
	s3Region := fs.String("s3-region", "us-east-1", "AWS region for S3")
	if err := fs.Parse(args); err != nil {
		return err
	}

	// Environment variables override flags (for Railway / container deployment)
	if v := getenv("PORT"); v != "" {
		p, err := strconv.Atoi(v)
		if err != nil {
			return fmt.Errorf("invalid PORT env: %w", err)
		}
		*port = p
	}
	if v := getenv("DATABASE_URL"); v != "" {
		*dbDSN = v
	}
	if v := getenv("PEPPER"); v != "" {
		*pepper = v
	}
	if v := getenv("PLATES_FILE"); v != "" {
		*platesFile = v
	}
	if v := getenv("APNS_KEY_FILE"); v != "" {
		*apnsKeyFile = v
	}
	if v := getenv("APNS_KEY_ID"); v != "" {
		*apnsKeyID = v
	}
	if v := getenv("APNS_TEAM_ID"); v != "" {
		*apnsTeamID = v
	}
	if v := getenv("APNS_BUNDLE_ID"); v != "" {
		*apnsBundleID = v
	}
	if v := getenv("APNS_PRODUCTION"); v != "" {
		*apnsProduction = v == "true" || v == "1"
	}
	if v := getenv("FCM_SERVICE_ACCOUNT"); v != "" {
		*fcmServiceAccount = v
	}
	if v := getenv("REPORT_UPLOAD_DIR"); v != "" {
		*reportUploadDir = v
	}
	if v := getenv("FCM_SERVICE_ACCOUNT_JSON"); v != "" && *fcmServiceAccount == "" {
		f, err := os.CreateTemp("", "fcm-sa-*.json")
		if err != nil {
			return fmt.Errorf("failed to write FCM service account: %w", err)
		}
		defer os.Remove(f.Name())
		if _, err := f.WriteString(v); err != nil {
			f.Close()
			return fmt.Errorf("failed to write FCM service account: %w", err)
		}
		f.Close()
		*fcmServiceAccount = f.Name()
	}
	if v := getenv("S3_BUCKET"); v != "" {
		*s3Bucket = v
	}
	if v := getenv("AWS_REGION"); v != "" {
		*s3Region = v
	}

	database, err := db.Connect(*dbDSN)
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}
	defer database.Close()

	if err := database.Migrate(ctx); err != nil {
		return fmt.Errorf("failed to run migrations: %w", err)
	}
	log.Println("database migrations complete")
	if *migrateOnly {
		return nil
	}

	if *pepper == "" {
		return fmt.Errorf("PEPPER is required: set via --pepper flag or PEPPER environment variable")
	}

	store, err := targets.New(*platesFile, []byte(*pepper))
	if err != nil {
		return fmt.Errorf("failed to load targets from %s: %w", *platesFile, err)
	}

	if err := seedDatabase(ctx, database, store); err != nil {
		return fmt.Errorf("failed to seed database: %w", err)
	}

	subStore := subscribers.New()
	defer subStore.Close()

	var apnsClient *push.APNsClient
	if *apnsKeyFile != "" {
		var err error
		apnsClient, err = push.NewAPNsClient(*apnsKeyFile, *apnsKeyID, *apnsTeamID, *apnsBundleID, *apnsProduction)
		if err != nil {
			return fmt.Errorf("failed to create APNs client: %w", err)
		}
		log.Println("APNs client initialized")
	}

	var fcmClient *push.FCMClient
	if *fcmServiceAccount != "" {
		var err error
		fcmClient, err = push.NewFCMClient(*fcmServiceAccount)
		if err != nil {
			return fmt.Errorf("failed to create FCM client: %w", err)
		}
		log.Println("FCM client initialized")
	}

	var notifier handler.PushNotifier
	if apnsClient != nil || fcmClient != nil {
		n := push.NewNotifier(apnsClient, fcmClient, database, subStore)
		defer n.Close()
		notifier = n
		log.Println("push notifier initialized")
	}

	if err := os.MkdirAll(*reportUploadDir, 0o750); err != nil {
		return fmt.Errorf("failed to create report upload dir: %w", err)
	}

	// Initialize S3 client if bucket is configured
	var s3Client storage.S3Client
	if *s3Bucket != "" {
		s3Client, err = storage.NewS3Client(ctx, *s3Bucket, *s3Region)
		if err != nil {
			return fmt.Errorf("failed to create S3 client: %w", err)
		}
		log.Printf("S3 client initialized (bucket=%s, region=%s)", *s3Bucket, *s3Region)
	}

	stopiceSubmitter := stopice.NewSubmitter(
		"https://www.stopice.net/platetracker/index.cgi",
		func(reportID int64, status, errMsg string) {
			if err := database.UpdateReportStopICE(ctx, reportID, status, errMsg); err != nil {
				log.Printf("failed to update StopICE status for report %d: %v", reportID, err)
			}
		},
	)

	mux := http.NewServeMux()
	registerV1Routes(mux, database, store, notifier, subStore, *reportUploadDir, stopiceSubmitter, s3Client)
	mux.HandleFunc("/healthz", handler.HealthHandler(store))

	srv := &http.Server{
		Addr:              fmt.Sprintf(":%d", *port),
		Handler:           handler.RequestLoggingMiddleware(log.Default())(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
		for sig := range sigCh {
			if sig == syscall.SIGHUP {
				log.Println("received SIGHUP, reloading targets")
				if err := store.Reload(); err != nil {
					log.Printf("reload failed: %v", err)
					continue
				}
				if err := seedDatabase(ctx, database, store); err != nil {
					log.Printf("failed to re-seed database: %v", err)
					continue
				}
				continue
			}
			log.Println("shutting down gracefully")
			shutdownCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
			defer cancel()
			if err := srv.Shutdown(shutdownCtx); err != nil {
				log.Printf("graceful shutdown failed: %v, forcing close", err)
				srv.Close()
			}
			return
		}
	}()

	log.Printf("listening on :%d, %d targets loaded", *port, store.Count())
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		return fmt.Errorf("server error: %w", err)
	}
	return nil
}

// dbSightingQuerier adapts db.DB to the handler.SightingQuerier interface.
type dbSightingQuerier struct {
	db *db.DB
}

func (q *dbSightingQuerier) RecentSightings(ctx context.Context, minLat, maxLat, minLng, maxLng float64, since time.Time) ([]handler.SightingResult, error) {
	rows, err := q.db.RecentSightings(ctx, minLat, maxLat, minLng, maxLng, since)
	if err != nil {
		return nil, err
	}
	results := make([]handler.SightingResult, len(rows))
	for i, r := range rows {
		results[i] = handler.SightingResult{
			Plate:     r.Plate,
			Latitude:  r.Latitude,
			Longitude: r.Longitude,
			SeenAt:    r.SeenAt,
		}
	}
	return results, nil
}

// dbMapQuerier adapts db.DB to the handler.MapSightingQuerier interface.
type dbMapQuerier struct {
	db *db.DB
}

func (q *dbMapQuerier) MapSightings(ctx context.Context, minLat, maxLat, minLng, maxLng float64, since time.Time) ([]handler.MapSightingEntry, error) {
	rows, err := q.db.MapSightings(ctx, minLat, maxLat, minLng, maxLng, since)
	if err != nil {
		return nil, err
	}
	results := make([]handler.MapSightingEntry, len(rows))
	for i, r := range rows {
		results[i] = handler.MapSightingEntry{
			Latitude:  r.Latitude,
			Longitude: r.Longitude,
			SeenAt:    r.SeenAt,
		}
	}
	return results, nil
}

func (q *dbMapQuerier) MapReports(ctx context.Context, minLat, maxLat, minLng, maxLng float64, since time.Time) ([]handler.MapReportEntry, error) {
	rows, err := q.db.MapReports(ctx, minLat, maxLat, minLng, maxLng, since)
	if err != nil {
		return nil, err
	}
	results := make([]handler.MapReportEntry, len(rows))
	for i, r := range rows {
		results[i] = handler.MapReportEntry{
			Latitude:    r.Latitude,
			Longitude:   r.Longitude,
			CreatedAt:   r.CreatedAt,
			Description: r.Description,
			PhotoPath:   r.PhotoPath,
		}
	}
	return results, nil
}

// s3PhotoSigner adapts storage.S3Client to handler.PhotoSigner.
type s3PhotoSigner struct {
	client storage.S3Client
}

func (s *s3PhotoSigner) PresignedPhotoURL(ctx context.Context, key string) (string, error) {
	return s.client.PresignedURL(ctx, key, 60*time.Minute)
}

func registerV1Routes(mux *http.ServeMux, database *db.DB, store *targets.Store, notifier handler.PushNotifier, subStore *subscribers.Store, reportUploadDir string, stopiceSubmitter *stopice.Submitter, s3Client storage.S3Client) {
	version := handler.APIVersionMiddleware("v1")
	mux.Handle("/api/v1/plates", version(handler.PlatesHandler(database, store, notifier)))
	mux.Handle("/api/v1/devices", version(handler.DevicesHandler(database)))
	mux.Handle("/api/v1/subscribe", version(handler.SubscribeHandler(subStore, &dbSightingQuerier{db: database}, database)))

	// Reports handler: use S3 for photos if configured, else fall back to disk
	var photoUploader handler.PhotoUploader
	if s3Client != nil {
		photoUploader = s3Client
	}
	mux.Handle("/api/v1/reports", version(handler.ReportsHandler(&dbReportStore{db: database}, reportUploadDir, stopiceSubmitter, photoUploader)))

	// Map sightings handler
	var signer handler.PhotoSigner
	if s3Client != nil {
		signer = &s3PhotoSigner{client: s3Client}
	}
	mux.Handle("/api/v1/map-sightings", version(handler.MapSightingsHandler(&dbMapQuerier{db: database}, signer)))
}

// dbReportStore adapts db.DB to the handler.ReportStore interface.
type dbReportStore struct {
	db *db.DB
}

func (s *dbReportStore) CreateReport(ctx context.Context, report *handler.Report) error {
	dbReport := &db.Report{
		Description:   report.Description,
		PlateNumber:   report.PlateNumber,
		Latitude:      report.Latitude,
		Longitude:     report.Longitude,
		PhotoPath:     report.PhotoPath,
		HardwareID:    report.HardwareID,
		StopICEStatus: report.StopICEStatus,
	}
	if err := s.db.CreateReport(ctx, dbReport); err != nil {
		return err
	}
	report.ID = dbReport.ID
	return nil
}

func seedDatabase(ctx context.Context, database *db.DB, store *targets.Store) error {
	records := store.Records()
	dbRecords := make([]db.PlateRecord, len(records))
	for i, r := range records {
		dbRecords[i] = db.PlateRecord{Plate: r.Plate, Hash: r.Hash}
	}
	mapping, err := database.UpsertPlates(ctx, dbRecords)
	if err != nil {
		return err
	}
	store.SetPlateIDs(mapping)
	log.Printf("seeded %d plates into database", len(mapping))
	return nil
}
