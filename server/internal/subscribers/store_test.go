package subscribers

import (
	"testing"
	"time"
)

func TestStore_SetAndGet(t *testing.T) {
	s := New()
	defer s.Close()

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
	s := New()
	defer s.Close()

	_, ok := s.Get("nonexistent")
	if ok {
		t.Fatal("expected missing subscriber to return false")
	}
}

func TestStore_Overwrite(t *testing.T) {
	s := New()
	defer s.Close()

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

func TestStore_ExpiredEntry(t *testing.T) {
	s := New()
	defer s.Close()

	s.mu.Lock()
	s.subs["device-1"] = Subscriber{
		Lat:         36.16,
		Lng:         -86.78,
		RadiusMiles: 10.0,
		ExpiresAt:   time.Now().Add(-1 * time.Minute),
	}
	s.mu.Unlock()

	_, ok := s.Get("device-1")
	if ok {
		t.Fatal("expected expired subscriber to return false")
	}
}

func TestStore_All(t *testing.T) {
	s := New()
	defer s.Close()

	s.Set("device-1", 36.16, -86.78, 10.0)
	s.Set("device-2", 34.05, -118.24, 50.0)

	s.mu.Lock()
	s.subs["device-expired"] = Subscriber{
		Lat:       40.71,
		Lng:       -74.01,
		ExpiresAt: time.Now().Add(-1 * time.Minute),
	}
	s.mu.Unlock()

	all := s.All()
	if len(all) != 2 {
		t.Fatalf("expected 2 active subscribers, got %d", len(all))
	}
	if _, ok := all["device-expired"]; ok {
		t.Error("expired subscriber should not appear in All()")
	}
}

func TestStore_TTLRefreshed(t *testing.T) {
	s := New()
	defer s.Close()

	s.Set("device-1", 36.16, -86.78, 10.0)
	firstSub, _ := s.Get("device-1")

	time.Sleep(10 * time.Millisecond)

	s.Set("device-1", 36.16, -86.78, 10.0)
	secondSub, _ := s.Get("device-1")

	if !secondSub.ExpiresAt.After(firstSub.ExpiresAt) {
		t.Error("re-subscribing should refresh the TTL")
	}
}
