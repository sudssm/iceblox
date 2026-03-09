package handler

import (
	"log"
	"net/http"
	"runtime/debug"
	"time"
)

type statusRecorder struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func newStatusRecorder(w http.ResponseWriter) *statusRecorder {
	return &statusRecorder{
		ResponseWriter: w,
		status:         http.StatusOK,
	}
}

func (r *statusRecorder) WriteHeader(status int) {
	if r.wroteHeader {
		r.ResponseWriter.WriteHeader(status)
		return
	}
	r.status = status
	r.wroteHeader = true
	r.ResponseWriter.WriteHeader(status)
}

func (r *statusRecorder) Write(data []byte) (int, error) {
	if !r.wroteHeader {
		r.WriteHeader(http.StatusOK)
	}
	return r.ResponseWriter.Write(data)
}

func RequestLoggingMiddleware(logger *log.Logger) func(http.Handler) http.Handler {
	if logger == nil {
		logger = log.Default()
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			recorder := newStatusRecorder(w)
			deviceID := r.Header.Get("X-Device-ID")

			defer func() {
				durationMS := time.Since(start).Milliseconds()

				if recovered := recover(); recovered != nil {
					stack := debug.Stack()
					if !recorder.wroteHeader {
						writeError(recorder, http.StatusInternalServerError, "internal server error")
					} else {
						recorder.status = http.StatusInternalServerError
					}
					logger.Printf(
						"http_panic method=%s path=%s status=%d duration_ms=%d device_id=%q panic=%v stack=%q",
						r.Method,
						r.URL.Path,
						recorder.status,
						durationMS,
						deviceID,
						recovered,
						stack,
					)
				} else if recorder.status >= http.StatusInternalServerError {
					logger.Printf(
						"http_server_error method=%s path=%s status=%d duration_ms=%d device_id=%q",
						r.Method,
						r.URL.Path,
						recorder.status,
						durationMS,
						deviceID,
					)
				}

				logger.Printf(
					"http_request method=%s path=%s status=%d duration_ms=%d device_id=%q",
					r.Method,
					r.URL.Path,
					recorder.status,
					durationMS,
					deviceID,
				)
			}()

			next.ServeHTTP(recorder, r)
		})
	}
}
