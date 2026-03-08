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
)

func main() {
	port := flag.Int("port", 8080, "server listen port")
	logFile := flag.String("log-file", "plates.jsonl", "path to JSONL log file")
	flag.Parse()

	logger, err := handler.NewJSONLLogger(*logFile)
	if err != nil {
		log.Fatalf("failed to open log file %s: %v", *logFile, err)
	}
	defer logger.Close()

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/plates", handler.PlatesHandler(logger))
	mux.HandleFunc("/healthz", handler.HealthHandler())

	srv := &http.Server{
		Addr:    fmt.Sprintf(":%d", *port),
		Handler: mux,
	}

	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		log.Println("shutting down")
		srv.Close()
	}()

	log.Printf("listening on :%d, logging to %s", *port, *logFile)
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
}
