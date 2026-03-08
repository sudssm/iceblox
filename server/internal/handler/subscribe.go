package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"iceblox/server/internal/geo"
)

type subscribeRequest struct {
	Latitude    *float64 `json:"latitude"`
	Longitude   *float64 `json:"longitude"`
	RadiusMiles *float64 `json:"radius_miles"`
}

type sightingResponse struct {
	Plate     string  `json:"plate"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	SeenAt    string  `json:"seen_at"`
}

type subscribeResponse struct {
	Status          string             `json:"status"`
	RecentSightings []sightingResponse `json:"recent_sightings"`
}

// SubscriberStore stores subscriber location and radius for proximity alerts.
type SubscriberStore interface {
	Set(deviceID string, lat, lng, radiusMiles float64)
}

// SightingQuerier queries recent sightings within a bounding box.
type SightingQuerier interface {
	RecentSightings(ctx context.Context, minLat, maxLat, minLng, maxLng float64, since time.Time) ([]SightingResult, error)
}

// SightingResult holds a sighting returned by SightingQuerier.
type SightingResult struct {
	Plate     string
	Latitude  float64
	Longitude float64
	SeenAt    time.Time
}

func SubscribeHandler(subs SubscriberStore, querier SightingQuerier) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}

		deviceID := r.Header.Get("X-Device-ID")
		if deviceID == "" {
			writeError(w, http.StatusBadRequest, "X-Device-ID header is required")
			return
		}

		var req subscribeRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid JSON body")
			return
		}

		if err := validateSubscribeRequest(req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}

		lat := *req.Latitude
		lng := *req.Longitude
		radius := *req.RadiusMiles

		subs.Set(deviceID, lat, lng, radius)

		bb := geo.BoundingBoxFromCenter(lat, lng, radius)
		since := time.Now().Add(-1 * time.Hour)

		sightings, err := querier.RecentSightings(r.Context(), bb.MinLat, bb.MaxLat, bb.MinLng, bb.MaxLng, since)
		if err != nil {
			log.Printf("failed to query recent sightings: %v", err)
			writeError(w, http.StatusInternalServerError, "failed to query recent sightings")
			return
		}

		var filtered []sightingResponse
		for _, s := range sightings {
			if geo.DistanceMiles(lat, lng, s.Latitude, s.Longitude) <= radius {
				filtered = append(filtered, sightingResponse{
					Plate:     s.Plate,
					Latitude:  s.Latitude,
					Longitude: s.Longitude,
					SeenAt:    s.SeenAt.UTC().Format(time.RFC3339),
				})
			}
		}

		if filtered == nil {
			filtered = []sightingResponse{}
		}

		resp := subscribeResponse{
			Status:          "ok",
			RecentSightings: filtered,
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(resp); err != nil {
			log.Printf("failed to encode subscribe response: %v", err)
		}
	}
}

func validateSubscribeRequest(req subscribeRequest) error {
	if req.Latitude == nil {
		return fmt.Errorf("latitude is required")
	}
	if req.Longitude == nil {
		return fmt.Errorf("longitude is required")
	}
	if req.RadiusMiles == nil {
		return fmt.Errorf("radius_miles is required")
	}
	if *req.Latitude < -90 || *req.Latitude > 90 {
		return fmt.Errorf("latitude must be in range [-90, 90]")
	}
	if *req.Longitude < -180 || *req.Longitude > 180 {
		return fmt.Errorf("longitude must be in range [-180, 180]")
	}
	if *req.RadiusMiles < 1 || *req.RadiusMiles > 500 {
		return fmt.Errorf("radius_miles must be in range [1, 500]")
	}
	return nil
}
