package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"cameras/server/internal/db"
	"cameras/server/internal/handler"
	"cameras/server/internal/push"
	"cameras/server/internal/subscribers"
	"cameras/server/internal/targets"
)

func main() {
	port := flag.Int("port", 8080, "server listen port")
	platesFile := flag.String("plates-file", "data/plates.txt", "path to plaintext plates file")
	pepper := flag.String("pepper", "default-pepper-change-me", "HMAC pepper for hashing plates")
	dbDSN := flag.String("db-dsn", "postgres://postgres:cameras@localhost:5432/cameras?sslmode=disable", "PostgreSQL connection string")

	apnsKeyFile := flag.String("apns-key-file", "", "path to APNs .p8 key file")
	apnsKeyID := flag.String("apns-key-id", "", "APNs key ID")
	apnsTeamID := flag.String("apns-team-id", "", "APNs team ID")
	apnsBundleID := flag.String("apns-bundle-id", "", "APNs bundle ID")
	apnsProduction := flag.Bool("apns-production", false, "use APNs production endpoint")
	fcmServiceAccount := flag.String("fcm-service-account", "", "path to FCM service account JSON file")
	flag.Parse()

	// Environment variables override flags (for Railway / container deployment)
	if v := os.Getenv("PORT"); v != "" {
		if p, err := fmt.Sscanf(v, "%d", port); p != 1 || err != nil {
			log.Fatal("invalid PORT env")
		}
	}
	if v := os.Getenv("DATABASE_URL"); v != "" {
		*dbDSN = v
	}
	if v := os.Getenv("PEPPER"); v != "" {
		*pepper = v
	}
	if v := os.Getenv("PLATES_FILE"); v != "" {
		*platesFile = v
	}

	ctx := context.Background()

	database, err := db.Connect(*dbDSN)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer database.Close()

	if err := database.Migrate(ctx); err != nil {
		log.Fatalf("failed to run migrations: %v", err)
	}
	log.Println("database migrations complete")

	store, err := targets.New(*platesFile, []byte(*pepper))
	if err != nil {
		log.Fatalf("failed to load targets from %s: %v", *platesFile, err)
	}

	if err := seedDatabase(ctx, database, store); err != nil {
		log.Fatalf("failed to seed database: %v", err)
	}

	subStore := subscribers.New()
	defer subStore.Close()

	var apnsClient *push.APNsClient
	if *apnsKeyFile != "" {
		var err error
		apnsClient, err = push.NewAPNsClient(*apnsKeyFile, *apnsKeyID, *apnsTeamID, *apnsBundleID, *apnsProduction)
		if err != nil {
			log.Fatalf("failed to create APNs client: %v", err)
		}
		log.Println("APNs client initialized")
	}

	var fcmClient *push.FCMClient
	if *fcmServiceAccount != "" {
		var err error
		fcmClient, err = push.NewFCMClient(*fcmServiceAccount)
		if err != nil {
			log.Fatalf("failed to create FCM client: %v", err)
		}
		log.Println("FCM client initialized")
	}

	var notifier handler.PushNotifier
	if apnsClient != nil || fcmClient != nil {
		notifier = push.NewNotifier(apnsClient, fcmClient, database)
		log.Println("push notifier initialized")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/plates", handler.PlatesHandler(database, store, notifier))
	mux.HandleFunc("/api/v1/devices", handler.DevicesHandler(database))
	mux.HandleFunc("/api/v1/subscribe", handler.SubscribeHandler(subStore, &dbSightingQuerier{db: database}))
	mux.HandleFunc("/healthz", handler.HealthHandler(store))

	srv := &http.Server{
		Addr:              fmt.Sprintf(":%d", *port),
		Handler:           mux,
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
				if err := seedDatabase(context.Background(), database, store); err != nil {
					log.Printf("failed to re-seed database: %v", err)
					continue
				}
				continue
			}
			log.Println("shutting down gracefully")
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
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
		log.Fatalf("server error: %v", err)
	}
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
