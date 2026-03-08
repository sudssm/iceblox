package subscribers

import (
	"sync"
	"time"
)

const defaultTTL = 1 * time.Hour

// Subscriber holds a device's subscription to proximity alerts.
type Subscriber struct {
	Lat         float64
	Lng         float64
	RadiusMiles float64
	ExpiresAt   time.Time
}

// Store is an in-memory subscriber store with automatic TTL cleanup.
type Store struct {
	mu   sync.RWMutex
	subs map[string]Subscriber
	done chan struct{}
}

// New creates a new subscriber store and starts a background goroutine
// that cleans expired entries every 5 minutes.
func New() *Store {
	s := &Store{
		subs: make(map[string]Subscriber),
		done: make(chan struct{}),
	}
	go s.cleanup()
	return s
}

// Set adds or updates a subscriber with a 1-hour TTL from now.
func (s *Store) Set(deviceID string, lat, lng, radiusMiles float64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.subs[deviceID] = Subscriber{
		Lat:         lat,
		Lng:         lng,
		RadiusMiles: radiusMiles,
		ExpiresAt:   time.Now().Add(defaultTTL),
	}
}

// Get returns the subscriber for a device ID if it exists and has not expired.
func (s *Store) Get(deviceID string) (Subscriber, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	sub, ok := s.subs[deviceID]
	if !ok || time.Now().After(sub.ExpiresAt) {
		return Subscriber{}, false
	}
	return sub, true
}

// All returns a copy of all active (non-expired) subscribers.
func (s *Store) All() map[string]Subscriber {
	s.mu.RLock()
	defer s.mu.RUnlock()
	now := time.Now()
	out := make(map[string]Subscriber)
	for id, sub := range s.subs {
		if now.Before(sub.ExpiresAt) {
			out[id] = sub
		}
	}
	return out
}

// Close stops the background cleanup goroutine.
func (s *Store) Close() {
	close(s.done)
}

func (s *Store) cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-s.done:
			return
		case <-ticker.C:
			s.mu.Lock()
			now := time.Now()
			for id, sub := range s.subs {
				if now.After(sub.ExpiresAt) {
					delete(s.subs, id)
				}
			}
			s.mu.Unlock()
		}
	}
}
