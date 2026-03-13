package subscribers

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/redis/go-redis/v9"
)

const defaultTTL = 1 * time.Hour

// Subscriber holds a device's subscription to proximity alerts.
type Subscriber struct {
	Lat         float64 `json:"lat"`
	Lng         float64 `json:"lng"`
	RadiusMiles float64 `json:"radius_miles"`
}

// Store is a Redis-backed subscriber store with native TTL expiry.
type Store struct {
	client *redis.Client
}

// New creates a new Redis-backed subscriber store.
func New(redisURL string) (*Store, error) {
	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, fmt.Errorf("invalid redis URL: %w", err)
	}
	client := redis.NewClient(opts)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		client.Close()
		return nil, fmt.Errorf("redis ping failed: %w", err)
	}
	return &Store{client: client}, nil
}

func subKey(deviceID string) string {
	return "sub:" + deviceID
}

const activeSetKey = "sub:active"

// Set adds or updates a subscriber with a 1-hour TTL.
func (s *Store) Set(deviceID string, lat, lng, radiusMiles float64) {
	sub := Subscriber{Lat: lat, Lng: lng, RadiusMiles: radiusMiles}
	data, err := json.Marshal(sub)
	if err != nil {
		log.Printf("subscribers: marshal error for %s: %v", deviceID, err)
		return
	}
	ctx := context.Background()
	pipe := s.client.Pipeline()
	pipe.Set(ctx, subKey(deviceID), data, defaultTTL)
	pipe.SAdd(ctx, activeSetKey, deviceID)
	if _, err := pipe.Exec(ctx); err != nil {
		log.Printf("subscribers: redis SET error for %s: %v", deviceID, err)
	}
}

// Get returns the subscriber for a device ID if it exists and has not expired.
func (s *Store) Get(deviceID string) (Subscriber, bool) {
	ctx := context.Background()
	data, err := s.client.Get(ctx, subKey(deviceID)).Bytes()
	if err != nil {
		return Subscriber{}, false
	}
	var sub Subscriber
	if err := json.Unmarshal(data, &sub); err != nil {
		log.Printf("subscribers: unmarshal error for %s: %v", deviceID, err)
		return Subscriber{}, false
	}
	return sub, true
}

// All returns all active (non-expired) subscribers.
func (s *Store) All() map[string]Subscriber {
	ctx := context.Background()
	ids, err := s.client.SMembers(ctx, activeSetKey).Result()
	if err != nil {
		log.Printf("subscribers: redis SMEMBERS error: %v", err)
		return map[string]Subscriber{}
	}
	if len(ids) == 0 {
		return map[string]Subscriber{}
	}

	keys := make([]string, len(ids))
	for i, id := range ids {
		keys[i] = subKey(id)
	}
	vals, err := s.client.MGet(ctx, keys...).Result()
	if err != nil {
		log.Printf("subscribers: redis MGET error: %v", err)
		return map[string]Subscriber{}
	}

	out := make(map[string]Subscriber)
	var stale []interface{}
	for i, val := range vals {
		if val == nil {
			stale = append(stale, ids[i])
			continue
		}
		str, ok := val.(string)
		if !ok {
			stale = append(stale, ids[i])
			continue
		}
		var sub Subscriber
		if err := json.Unmarshal([]byte(str), &sub); err != nil {
			log.Printf("subscribers: unmarshal error for %s: %v", ids[i], err)
			stale = append(stale, ids[i])
			continue
		}
		out[ids[i]] = sub
	}

	if len(stale) > 0 {
		if err := s.client.SRem(ctx, activeSetKey, stale...).Err(); err != nil {
			log.Printf("subscribers: redis SREM error: %v", err)
		}
	}
	return out
}

// Close closes the Redis client connection.
func (s *Store) Close() error {
	return s.client.Close()
}
