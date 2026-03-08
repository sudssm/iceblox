package handler

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type PlateRequest struct {
	PlateHash string  `json:"plate_hash"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type PlateLogEntry struct {
	PlateHash  string  `json:"plate_hash"`
	Latitude   float64 `json:"latitude"`
	Longitude  float64 `json:"longitude"`
	ReceivedAt string  `json:"received_at"`
}

type LogWriter interface {
	WriteEntry(entry PlateLogEntry) error
}

func PlatesHandler(logger LogWriter) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}

		var req PlateRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid JSON body")
			return
		}

		if err := validatePlateRequest(req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}

		entry := PlateLogEntry{
			PlateHash:  req.PlateHash,
			Latitude:   req.Latitude,
			Longitude:  req.Longitude,
			ReceivedAt: time.Now().UTC().Format(time.RFC3339),
		}

		if err := logger.WriteEntry(entry); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to log entry")
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	}
}

func validatePlateRequest(req PlateRequest) error {
	if len(req.PlateHash) != 64 {
		return fmt.Errorf("plate_hash must be 64 hex characters, got %d", len(req.PlateHash))
	}
	if _, err := hex.DecodeString(req.PlateHash); err != nil {
		return fmt.Errorf("plate_hash must be valid hexadecimal")
	}
	if req.Latitude < -90 || req.Latitude > 90 {
		return fmt.Errorf("latitude must be in range [-90, 90]")
	}
	if req.Longitude < -180 || req.Longitude > 180 {
		return fmt.Errorf("longitude must be in range [-180, 180]")
	}
	return nil
}

func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}
