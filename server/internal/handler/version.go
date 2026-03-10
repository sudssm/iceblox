package handler

import (
	"net/http"
	"time"
)

// APIVersionMiddleware sets the API-Version response header on every request.
func APIVersionMiddleware(version string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("API-Version", version)
			next.ServeHTTP(w, r)
		})
	}
}

// DeprecationMiddleware adds Deprecation, Sunset, and Link headers to signal
// that an API version is deprecated. Apply to version-specific route groups
// when a successor version is available.
func DeprecationMiddleware(sunsetDate time.Time, successorPath string) func(http.Handler) http.Handler {
	sunset := sunsetDate.UTC().Format(http.TimeFormat)

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Deprecation", "true")
			w.Header().Set("Sunset", sunset)
			if successorPath != "" {
				w.Header().Set("Link", "<"+successorPath+">; rel=\"successor-version\"")
			}
			next.ServeHTTP(w, r)
		})
	}
}
