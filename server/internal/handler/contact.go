package handler

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"

	"github.com/google/uuid"
)

type ContactStore interface {
	CreateContact(ctx context.Context, contact *Contact) error
}

type Contact struct {
	ID         int64
	Name       string
	Email      string
	Message    string
	LogPath    string
	HardwareID string
}

func ContactHandler(store ContactStore, s3 PhotoUploader) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}

		hardwareID := r.Header.Get("X-Device-ID")
		if hardwareID == "" {
			writeError(w, http.StatusBadRequest, "missing X-Device-ID header")
			return
		}

		r.Body = http.MaxBytesReader(w, r.Body, 5<<20)

		var body struct {
			Name    string `json:"name"`
			Email   string `json:"email"`
			Message string `json:"message"`
			Logs    string `json:"logs"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeError(w, http.StatusBadRequest, "invalid JSON body")
			return
		}

		if strings.TrimSpace(body.Message) == "" {
			writeError(w, http.StatusBadRequest, "message is required")
			return
		}

		var logPath string
		if body.Logs != "" && s3 != nil {
			key := "contact-logs/" + uuid.New().String() + ".txt"
			if _, err := s3.Upload(r.Context(), key, strings.NewReader(body.Logs), "text/plain"); err != nil {
				log.Printf("failed to upload contact logs to S3: %v", err)
				writeError(w, http.StatusInternalServerError, "failed to save logs")
				return
			}
			logPath = key
		}

		contact := &Contact{
			Name:       body.Name,
			Email:      body.Email,
			Message:    body.Message,
			LogPath:    logPath,
			HardwareID: sanitizeHeader(hardwareID),
		}

		if err := store.CreateContact(r.Context(), contact); err != nil {
			log.Printf("failed to create contact: %v", err)
			writeError(w, http.StatusInternalServerError, "failed to save contact")
			return
		}

		log.Printf("POST /api/v1/contact id=%d device=%s", contact.ID, sanitizeHeader(hardwareID)) //nolint:gosec // hardwareID sanitized

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"status":     "ok",
			"contact_id": contact.ID,
		}); err != nil {
			log.Printf("failed to encode response: %v", err)
		}
	}
}
