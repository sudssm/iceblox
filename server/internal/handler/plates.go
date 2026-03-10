package handler

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"time"
)

type PlateRequest struct {
	PlateHash     string  `json:"plate_hash"`
	Latitude      float64 `json:"latitude"`
	Longitude     float64 `json:"longitude"`
	Timestamp     string  `json:"timestamp,omitempty"`
	Substitutions int     `json:"substitutions"`
}

type BatchPlateRequest struct {
	Plates []PlateRequest `json:"plates"`
}

type PlateResult struct {
	Matched bool `json:"matched"`
}

type TargetChecker interface {
	Contains(hash string) bool
	PlateID(hash string) (int64, bool)
	Plate(hash string) (string, bool)
}

type SightingRecorder interface {
	RecordSighting(ctx context.Context, plateID int64, seenAt time.Time, lat, lng float64, hardwareID string, substitutions int) (int64, error)
}

type PushNotifier interface {
	NotifyAsync(sightingID int64, plateID int64, lat, lng float64)
}

func PlatesHandler(recorder SightingRecorder, targets TargetChecker, notifier PushNotifier) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}

		var batch BatchPlateRequest
		if err := json.NewDecoder(r.Body).Decode(&batch); err != nil {
			writeError(w, http.StatusBadRequest, "invalid JSON body")
			return
		}

		if len(batch.Plates) == 0 {
			writeError(w, http.StatusBadRequest, "plates array must not be empty")
			return
		}

		for _, req := range batch.Plates {
			if err := validatePlateRequest(req); err != nil {
				writeError(w, http.StatusBadRequest, err.Error())
				return
			}
		}

		hardwareID := sanitizeHeader(r.Header.Get("X-Device-ID"))
		if hardwareID == "" {
			hardwareID = "unknown"
		}

		log.Printf("POST /api/v1/plates count=%d device=%s", len(batch.Plates), hardwareID) //nolint:gosec // hardwareID sanitized above

		results := make([]PlateResult, len(batch.Plates))
		for i, req := range batch.Plates {
			matched := targets.Contains(req.PlateHash)
			results[i] = PlateResult{Matched: matched}

			if matched {
				plate, _ := targets.Plate(req.PlateHash)
				log.Printf("MATCH DETECTED plate=%s hash=%s lat=%.6f lon=%.6f", plate, req.PlateHash, req.Latitude, req.Longitude)

				plateID, _ := targets.PlateID(req.PlateHash)
				seenAt := parseTimestamp(req.Timestamp)

				sightingID, err := recorder.RecordSighting(r.Context(), plateID, seenAt, req.Latitude, req.Longitude, hardwareID, req.Substitutions)
				if err != nil {
					log.Printf("failed to record sighting: %v", err)
					writeError(w, http.StatusInternalServerError, "failed to record sighting")
					return
				}

				if notifier != nil {
					notifier.NotifyAsync(sightingID, plateID, req.Latitude, req.Longitude)
				}
			}
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "ok",
			"results": results,
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
	if req.Substitutions < 0 {
		return fmt.Errorf("substitutions must be >= 0")
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

var headerSanitizer = regexp.MustCompile(`[^a-zA-Z0-9\-_.]`)

func sanitizeHeader(s string) string {
	return headerSanitizer.ReplaceAllString(s, "")
}

func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(map[string]string{"error": msg}); err != nil {
		log.Printf("failed to encode error response: %v", err)
	}
}
