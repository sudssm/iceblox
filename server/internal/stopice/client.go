package stopice

import (
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

type StatusCallback func(reportID int64, status, errMsg string)

type Submitter struct {
	baseURL    string
	httpClient *http.Client
	onStatus   StatusCallback
}

func NewSubmitter(baseURL string, onStatus StatusCallback) *Submitter {
	return &Submitter{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		onStatus: onStatus,
	}
}

func (s *Submitter) SubmitAsync(reportID int64, plateNumber, description string, lat, lng float64) {
	go func() {
		err := s.submit(plateNumber, description, lat, lng)
		if err != nil {
			log.Printf("StopICE submission failed for report %d: %v", reportID, err)
			s.onStatus(reportID, "failed", err.Error())
			return
		}
		log.Printf("StopICE submission succeeded for report %d", reportID)
		s.onStatus(reportID, "submitted", "")
	}()
}

func (s *Submitter) submit(plateNumber, description string, lat, lng float64) error {
	address := fmt.Sprintf("%.6f, %.6f", lat, lng)

	form := url.Values{}
	form.Set("vehicle_license", plateNumber)
	form.Set("address", address)
	form.Set("comments", description)
	form.Set("get_location_gps", address)
	form.Set("guest", "1")
	form.Set("alert_token", strconv.FormatInt(time.Now().UnixMilli(), 10))

	resp, err := s.httpClient.PostForm(s.baseURL, form)
	if err != nil {
		return fmt.Errorf("POST to StopICE: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("StopICE returned status %d", resp.StatusCode)
	}

	return nil
}
