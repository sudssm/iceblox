//go:build integration

package subscribers

import (
	"testing"
	"time"

	"context"

	"github.com/redis/go-redis/v9"
)

const testRedisURL = "redis://localhost:6379/1"

func setupStore(t *testing.T) *Store {
	t.Helper()
	s, err := New(testRedisURL)
	if err != nil {
		t.Fatalf("failed to create store: %v", err)
	}
	t.Cleanup(func() {
		opts, _ := redis.ParseURL(testRedisURL)
		c := redis.NewClient(opts)
		c.FlushDB(context.Background())
		c.Close()
		s.Close()
	})
	return s
}

func TestStore_SetAndGet(t *testing.T) {
	s := setupStore(t)

	s.Set("device-1", 36.16, -86.78, 10.0)

	sub, ok := s.Get("device-1")
	if !ok {
		t.Fatal("expected subscriber to exist")
	}
	if sub.Lat != 36.16 || sub.Lng != -86.78 || sub.RadiusMiles != 10.0 {
		t.Errorf("got lat=%f lng=%f radius=%f", sub.Lat, sub.Lng, sub.RadiusMiles)
	}
}

func TestStore_GetMissing(t *testing.T) {
	s := setupStore(t)

	_, ok := s.Get("nonexistent")
	if ok {
		t.Fatal("expected missing subscriber to return false")
	}
}

func TestStore_Overwrite(t *testing.T) {
	s := setupStore(t)

	s.Set("device-1", 36.16, -86.78, 10.0)
	s.Set("device-1", 34.05, -118.24, 50.0)

	sub, ok := s.Get("device-1")
	if !ok {
		t.Fatal("expected subscriber to exist after overwrite")
	}
	if sub.Lat != 34.05 || sub.Lng != -118.24 || sub.RadiusMiles != 50.0 {
		t.Errorf("expected overwritten values, got lat=%f lng=%f radius=%f", sub.Lat, sub.Lng, sub.RadiusMiles)
	}
}

func TestStore_Expired(t *testing.T) {
	s := setupStore(t)

	ctx := context.Background()
	s.Set("device-1", 36.16, -86.78, 10.0)
	// Force expire by setting TTL to 1ms then waiting
	s.client.PExpire(ctx, subKey("device-1"), time.Millisecond)
	time.Sleep(10 * time.Millisecond)

	_, ok := s.Get("device-1")
	if ok {
		t.Fatal("expected expired subscriber to return false")
	}
}

func TestStore_All(t *testing.T) {
	s := setupStore(t)

	s.Set("device-1", 36.16, -86.78, 10.0)
	s.Set("device-2", 34.05, -118.24, 50.0)

	// Add an entry and force-expire it
	ctx := context.Background()
	s.Set("device-expired", 40.71, -74.01, 5.0)
	s.client.PExpire(ctx, subKey("device-expired"), time.Millisecond)
	time.Sleep(10 * time.Millisecond)

	all := s.All()
	if len(all) != 2 {
		t.Fatalf("expected 2 active subscribers, got %d", len(all))
	}
	if _, ok := all["device-expired"]; ok {
		t.Error("expired subscriber should not appear in All()")
	}
}

func TestStore_TTLRefresh(t *testing.T) {
	s := setupStore(t)

	ctx := context.Background()
	s.Set("device-1", 36.16, -86.78, 10.0)
	firstTTL, _ := s.client.TTL(ctx, subKey("device-1")).Result()

	time.Sleep(50 * time.Millisecond)

	s.Set("device-1", 36.16, -86.78, 10.0)
	secondTTL, _ := s.client.TTL(ctx, subKey("device-1")).Result()

	// After re-subscribing, TTL should be refreshed (>= first TTL which has been ticking down)
	if secondTTL < firstTTL {
		t.Errorf("re-subscribing should refresh TTL: first=%v second=%v", firstTTL, secondTTL)
	}
}
