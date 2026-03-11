package handler

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"iceblox/server/internal/db"
	"iceblox/server/internal/geo"
)

// MapSightingQuerier queries sightings and reports for the map view.
type MapSightingQuerier interface {
	MapSightings(ctx context.Context, minLat, maxLat, minLng, maxLng float64, since time.Time) ([]MapSightingEntry, error)
	MapReports(ctx context.Context, minLat, maxLat, minLng, maxLng float64, since time.Time) ([]MapReportEntry, error)
}

// MapSightingEntry is a sighting result for map display.
type MapSightingEntry struct {
	Latitude  float64
	Longitude float64
	SeenAt    time.Time
}

// MapReportEntry is a report result for map display.
type MapReportEntry struct {
	Latitude    float64
	Longitude   float64
	CreatedAt   time.Time
	Description string
	PhotoPath   string
}

// PhotoSigner generates presigned URLs for report photos.
type PhotoSigner interface {
	PresignedPhotoURL(ctx context.Context, key string) (string, error)
}

type mapSightingItem struct {
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
	Confidence  float64 `json:"confidence"`
	SeenAt      string  `json:"seen_at"`
	Type        string  `json:"type"`
	Description *string `json:"description,omitempty"`
	PhotoURL    *string `json:"photo_url,omitempty"`
}

type mapSightingsResponse struct {
	Status    string            `json:"status"`
	Sightings []mapSightingItem `json:"sightings"`
}

// MapSightingsHandler returns sightings and reports within a radius for map display.
func MapSightingsHandler(querier MapSightingQuerier, signer PhotoSigner) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}

		lat, err := parseRequiredFloat(r, "lat")
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid or missing lat parameter")
			return
		}
		lng, err := parseRequiredFloat(r, "lng")
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid or missing lng parameter")
			return
		}
		radius, err := parseRequiredFloat(r, "radius")
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid or missing radius parameter")
			return
		}

		if lat < -90 || lat > 90 {
			writeError(w, http.StatusBadRequest, "lat must be in range [-90, 90]")
			return
		}
		if lng < -180 || lng > 180 {
			writeError(w, http.StatusBadRequest, "lng must be in range [-180, 180]")
			return
		}
		if radius < 1 || radius > 500 {
			writeError(w, http.StatusBadRequest, "radius must be in range [1, 500]")
			return
		}

		bb := geo.BoundingBoxFromCenter(lat, lng, radius*1.2)
		since := time.Now().Add(-db.MapSightingWindow)

		sightings, err := querier.MapSightings(r.Context(), bb.MinLat, bb.MaxLat, bb.MinLng, bb.MaxLng, since)
		if err != nil {
			log.Printf("failed to query map sightings: %v", err)
			writeError(w, http.StatusInternalServerError, "failed to query sightings")
			return
		}

		reports, err := querier.MapReports(r.Context(), bb.MinLat, bb.MaxLat, bb.MinLng, bb.MaxLng, since)
		if err != nil {
			log.Printf("failed to query map reports: %v", err)
			writeError(w, http.StatusInternalServerError, "failed to query reports")
			return
		}

		items := make([]mapSightingItem, 0, len(sightings)+len(reports))

		for _, s := range sightings {
			items = append(items, mapSightingItem{
				Latitude:   s.Latitude,
				Longitude:  s.Longitude,
				Confidence: 1.0,
				SeenAt:     s.SeenAt.UTC().Format(time.RFC3339),
				Type:       "sighting",
			})
		}

		for _, rpt := range reports {
			item := mapSightingItem{
				Latitude:    rpt.Latitude,
				Longitude:   rpt.Longitude,
				Confidence:  1.0,
				SeenAt:      rpt.CreatedAt.UTC().Format(time.RFC3339),
				Type:        "report",
				Description: &rpt.Description,
			}
			if signer != nil && rpt.PhotoPath != "" {
				url, err := signer.PresignedPhotoURL(r.Context(), rpt.PhotoPath)
				if err != nil {
					log.Printf("failed to presign photo %s: %v", rpt.PhotoPath, err)
				} else {
					item.PhotoURL = &url
				}
			}
			items = append(items, item)
		}

		resp := mapSightingsResponse{
			Status:    "ok",
			Sightings: items,
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(resp); err != nil {
			log.Printf("failed to encode map sightings response: %v", err)
		}
	}
}

func parseRequiredFloat(r *http.Request, key string) (float64, error) {
	v := r.URL.Query().Get(key)
	if v == "" {
		return 0, strconv.ErrRange
	}
	return strconv.ParseFloat(v, 64)
}
