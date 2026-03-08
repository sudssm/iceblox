package handler

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
)

type DeviceTokenStore interface {
	UpsertDeviceToken(ctx context.Context, hardwareID, token, platform string) error
}

type deviceRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

func DevicesHandler(store DeviceTokenStore) http.HandlerFunc {
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

		var req deviceRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid JSON body")
			return
		}

		if req.Token == "" {
			writeError(w, http.StatusBadRequest, "token is required")
			return
		}
		if req.Platform != "ios" && req.Platform != "android" {
			writeError(w, http.StatusBadRequest, "platform must be ios or android")
			return
		}

		if err := store.UpsertDeviceToken(r.Context(), hardwareID, req.Token, req.Platform); err != nil {
			log.Printf("failed to upsert device token: %v", err)
			writeError(w, http.StatusInternalServerError, "failed to register device")
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(map[string]string{"status": "ok"}); err != nil {
			log.Printf("failed to encode response: %v", err)
		}
	}
}
