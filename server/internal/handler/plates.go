package handler

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

type PlateRequest struct {
	PlateHash string  `json:"plate_hash"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Timestamp string  `json:"timestamp,omitempty"`
}

type TargetChecker interface {
	Contains(hash string) bool
	PlateID(hash string) (int64, bool)
}

type SightingRecorder interface {
	RecordSighting(ctx context.Context, plateID int64, seenAt time.Time, lat, lng float64, hardwareID string) error
}

func PlatesHandler(recorder SightingRecorder, targets TargetChecker) http.HandlerFunc {
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

		matched := targets.Contains(req.PlateHash)
		log.Printf("POST /api/v1/plates hash=%s matched=%v lat=%.4f lon=%.4f", req.PlateHash, matched, req.Latitude, req.Longitude)

		if matched {
			plateID, _ := targets.PlateID(req.PlateHash)
			seenAt := parseTimestamp(req.Timestamp)
			hardwareID := r.Header.Get("X-Device-ID")
			if hardwareID == "" {
				hardwareID = "unknown"
			}

			if err := recorder.RecordSighting(r.Context(), plateID, seenAt, req.Latitude, req.Longitude, hardwareID); err != nil {
				log.Printf("failed to record sighting: %v", err)
				writeError(w, http.StatusInternalServerError, "failed to record sighting")
				return
			}
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "ok",
			"matched": matched,
		}); err != nil {
			log.Printf("failed to encode response: %v", err)
		}
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

func parseTimestamp(ts string) time.Time {
	if ts == "" {
		return time.Now().UTC()
	}
	t, err := time.Parse(time.RFC3339, ts)
	if err != nil {
		return time.Now().UTC()
	}
	return t
}

func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(map[string]string{"error": msg}); err != nil {
		log.Printf("failed to encode error response: %v", err)
	}
}
