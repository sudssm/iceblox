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
	"cameras/server/internal/targets"
)

func main() {
	port := flag.Int("port", 80, "server listen port")
	platesFile := flag.String("plates-file", "data/plates.txt", "path to plaintext plates file")
	pepper := flag.String("pepper", "default-pepper-change-me", "HMAC pepper for hashing plates")
	dbDSN := flag.String("db-dsn", "postgres://postgres:cameras@localhost:5432/cameras?sslmode=disable", "PostgreSQL connection string")
	flag.Parse()

	// Environment variables override flags (for Railway / container deployment)
	if v := os.Getenv("PORT"); v != "" {
		if p, err := fmt.Sscanf(v, "%d", port); p != 1 || err != nil {
			log.Fatalf("invalid PORT env: %s", v)
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

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/plates", handler.PlatesHandler(database, store))
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
