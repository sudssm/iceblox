package handler

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"github.com/google/uuid"
)

type ReportStore interface {
	CreateReport(ctx context.Context, report *Report) error
}

type Report struct {
	ID            int64
	Description   string
	PlateNumber   string
	Latitude      float64
	Longitude     float64
	PhotoPath     string
	HardwareID    string
	StopICEStatus string
}

type StopICESubmitter interface {
	SubmitAsync(reportID int64, plateNumber, description string, lat, lng float64)
}

// PhotoUploader uploads report photos and returns the stored key/path.
type PhotoUploader interface {
	Upload(ctx context.Context, key string, body io.Reader, contentType string) (string, error)
}

func ReportsHandler(store ReportStore, uploadDir string, submitter StopICESubmitter, s3 PhotoUploader) http.HandlerFunc {
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

		r.Body = http.MaxBytesReader(w, r.Body, 10<<20) //nolint:gosec // body size limited above
		if err := r.ParseMultipartForm(10 << 20); err != nil {
			writeError(w, http.StatusBadRequest, "invalid multipart form")
			return
		}

		description := r.FormValue("description") //nolint:gosec // body size limited above
		if description == "" {
			writeError(w, http.StatusBadRequest, "description is required")
			return
		}

		latStr := r.FormValue("latitude")
		lngStr := r.FormValue("longitude")
		lat, err := strconv.ParseFloat(latStr, 64)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid latitude")
			return
		}
		lng, err := strconv.ParseFloat(lngStr, 64)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid longitude")
			return
		}

		if lat < -90 || lat > 90 {
			writeError(w, http.StatusBadRequest, "latitude must be in range [-90, 90]")
			return
		}
		if lng < -180 || lng > 180 {
			writeError(w, http.StatusBadRequest, "longitude must be in range [-180, 180]")
			return
		}

		plateNumber := r.FormValue("plate_number")

		file, _, err := r.FormFile("photo")
		if err != nil {
			writeError(w, http.StatusBadRequest, "photo is required")
			return
		}
		defer file.Close()

		filename := uuid.New().String() + ".jpg"
		s3Key := "reports/" + filename

		if s3 != nil {
			if _, err := s3.Upload(r.Context(), s3Key, file, "image/jpeg"); err != nil {
				log.Printf("failed to upload photo to S3: %v", err)
				writeError(w, http.StatusInternalServerError, "failed to save photo")
				return
			}
		} else {
			photoPath := filepath.Join(uploadDir, filename)
			dst, err := os.Create(photoPath)
			if err != nil {
				log.Printf("failed to create photo file: %v", err)
				writeError(w, http.StatusInternalServerError, "failed to save photo")
				return
			}
			defer dst.Close()

			if _, err := io.Copy(dst, file); err != nil {
				log.Printf("failed to write photo file: %v", err)
				writeError(w, http.StatusInternalServerError, "failed to save photo")
				return
			}
		}

		report := &Report{
			Description:   description,
			PlateNumber:   plateNumber,
			Latitude:      lat,
			Longitude:     lng,
			PhotoPath:     s3Key,
			HardwareID:    sanitizeHeader(hardwareID),
			StopICEStatus: "pending",
		}

		if err := store.CreateReport(r.Context(), report); err != nil {
			log.Printf("failed to create report: %v", err)
			writeError(w, http.StatusInternalServerError, "failed to save report")
			return
		}

		log.Printf("POST /api/v1/reports id=%d device=%s lat=%.4f lon=%.4f", report.ID, sanitizeHeader(report.HardwareID), lat, lng) //nolint:gosec // hardwareID sanitized

		if submitter != nil {
			submitter.SubmitAsync(report.ID, plateNumber, description, lat, lng)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"status":    "ok",
			"report_id": report.ID,
		}); err != nil {
			log.Printf("failed to encode response: %v", err)
		}
	}
}
