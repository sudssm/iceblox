package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"cameras/server/internal/handler"
	"cameras/server/internal/targets"
)

func main() {
	port := flag.Int("port", 8080, "server listen port")
	logFile := flag.String("log-file", "plates.jsonl", "path to JSONL log file")
	platesFile := flag.String("plates-file", "data/plates.txt", "path to plaintext plates file")
	pepper := flag.String("pepper", "default-pepper-change-me", "HMAC pepper for hashing plates")
	flag.Parse()

	logger, err := handler.NewJSONLLogger(*logFile)
	if err != nil {
		log.Fatalf("failed to open log file %s: %v", *logFile, err)
	}
	defer logger.Close()

	store, err := targets.New(*platesFile, []byte(*pepper))
	if err != nil {
		log.Fatalf("failed to load targets from %s: %v", *platesFile, err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/plates", handler.PlatesHandler(logger, store))
	mux.HandleFunc("/healthz", handler.HealthHandler(store))

	srv := &http.Server{
		Addr:    fmt.Sprintf(":%d", *port),
		Handler: mux,
	}

	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
		for sig := range sigCh {
			if sig == syscall.SIGHUP {
				log.Println("received SIGHUP, reloading targets")
				if err := store.Reload(); err != nil {
					log.Printf("reload failed: %v", err)
				}
				continue
			}
			log.Println("shutting down")
			srv.Close()
			return
		}
	}()

	log.Printf("listening on :%d, logging to %s, %d targets loaded", *port, *logFile, store.Count())
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
}
