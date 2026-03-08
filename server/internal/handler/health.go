package handler

import (
	"encoding/json"
	"log"
	"net/http"
)

type TargetCounter interface {
	Count() int
}

func HealthHandler(targets TargetCounter) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"status":         "ok",
			"targets_loaded": targets.Count(),
		}); err != nil {
			log.Printf("failed to encode health response: %v", err)
		}
	}
}
