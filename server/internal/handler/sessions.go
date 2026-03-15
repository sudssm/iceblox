package handler

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
)

type SessionStarter interface {
	CreateSession(ctx context.Context, sessionID, deviceID string) error
}

type startSessionRequest struct {
	SessionID string `json:"session_id"`
	DeviceID  string `json:"device_id"`
}

func StartSessionHandler(starter SessionStarter) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}

		var req startSessionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid JSON body")
			return
		}

		if req.SessionID == "" {
			writeError(w, http.StatusBadRequest, "session_id is required")
			return
		}

		if req.DeviceID == "" {
			writeError(w, http.StatusBadRequest, "device_id is required")
			return
		}

		if err := starter.CreateSession(r.Context(), req.SessionID, req.DeviceID); err != nil {
			log.Printf("failed to create session: %v", err)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(map[string]string{"status": "ok"}); err != nil {
			log.Printf("failed to encode response: %v", err)
		}
	}
}

type SessionEnder interface {
	EndSession(ctx context.Context, sessionID string, maxDetConf, totalDetConf, maxOCRConf, totalOCRConf float64) error
}

type endSessionRequest struct {
	SessionID                string  `json:"session_id"`
	MaxDetectionConfidence   float64 `json:"max_detection_confidence"`
	TotalDetectionConfidence float64 `json:"total_detection_confidence"`
	MaxOCRConfidence         float64 `json:"max_ocr_confidence"`
	TotalOCRConfidence       float64 `json:"total_ocr_confidence"`
}

func EndSessionHandler(ender SessionEnder) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}

		var req endSessionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid JSON body")
			return
		}

		if req.SessionID == "" {
			writeError(w, http.StatusBadRequest, "session_id is required")
			return
		}

		if err := ender.EndSession(r.Context(), req.SessionID,
			req.MaxDetectionConfidence, req.TotalDetectionConfidence,
			req.MaxOCRConfidence, req.TotalOCRConfidence); err != nil {
			log.Printf("failed to end session: %v", err)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(map[string]string{"status": "ok"}); err != nil {
			log.Printf("failed to encode response: %v", err)
		}
	}
}
