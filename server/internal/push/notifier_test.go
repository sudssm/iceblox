package push

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"iceblox/server/internal/db"
	"iceblox/server/internal/subscribers"
)

type mockTokenStore struct {
	mu          sync.Mutex
	tokens      []db.DeviceToken
	deleted     []int64
	err         error
	pushes      map[int64][]db.SentPush
	recorded    []recordedPush
	cleanupCall bool
}

type recordedPush struct {
	DeviceTokenID int64
	PlateID       int64
	Lat, Lng      float64
}

func (m *mockTokenStore) AllDeviceTokens(_ context.Context) ([]db.DeviceToken, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.err != nil {
		return nil, m.err
	}
	return m.tokens, nil
}

func (m *mockTokenStore) DeleteDeviceToken(_ context.Context, id int64) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.deleted = append(m.deleted, id)
	return nil
}

func (m *mockTokenStore) RecentPushesForDevice(_ context.Context, deviceTokenID int64) ([]db.SentPush, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.pushes == nil {
		return nil, nil
	}
	return m.pushes[deviceTokenID], nil
}

func (m *mockTokenStore) RecordSentPush(_ context.Context, deviceTokenID, plateID int64, lat, lng float64) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.recorded = append(m.recorded, recordedPush{
		DeviceTokenID: deviceTokenID,
		PlateID:       plateID,
		Lat:           lat,
		Lng:           lng,
	})
	return nil
}

func (m *mockTokenStore) CleanupStalePushes(_ context.Context, _ time.Duration) (int64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.cleanupCall = true
	return 0, nil
}

type mockSubscriberStore struct {
	subs map[string]subscribers.Subscriber
}

func (m *mockSubscriberStore) All() map[string]subscribers.Subscriber {
	return m.subs
}

func TestNotifier_DispatchesToBothPlatforms(t *testing.T) {
	var apnsCalls, fcmCalls int
	var mu sync.Mutex

	apnsServer := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		apnsCalls++
		mu.Unlock()
		w.WriteHeader(http.StatusOK)
	}))
	defer apnsServer.Close()

	fcmTokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "tok",
			"expires_in":   3600,
		}); err != nil {
			t.Errorf("encode token response: %v", err)
		}
	}))
	defer fcmTokenServer.Close()

	fcmSendServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		fcmCalls++
		mu.Unlock()
		w.WriteHeader(http.StatusOK)
		if _, err := w.Write([]byte(`{}`)); err != nil {
			t.Errorf("write response: %v", err)
		}
	}))
	defer fcmSendServer.Close()

	apnsClient := newTestAPNsClient(t, apnsServer)
	fcmClient := newTestFCMClient(t, fcmTokenServer.URL, fcmSendServer.URL)

	store := &mockTokenStore{
		tokens: []db.DeviceToken{
			{ID: 1, HardwareID: "hw1", Token: "ios-tok", Platform: "ios"},
			{ID: 2, HardwareID: "hw2", Token: "android-tok", Platform: "android"},
		},
	}

	subs := &mockSubscriberStore{
		subs: map[string]subscribers.Subscriber{
			"hw1": {Lat: 36.16, Lng: -86.78, RadiusMiles: 100},
			"hw2": {Lat: 36.16, Lng: -86.78, RadiusMiles: 100},
		},
	}

	notifier := NewNotifier(apnsClient, fcmClient, store, subs)
	defer notifier.Close()
	notifier.dispatch(100, 1, 36.16, -86.78)

	mu.Lock()
	defer mu.Unlock()
	if apnsCalls != 1 {
		t.Errorf("expected 1 APNs call, got %d", apnsCalls)
	}
	if fcmCalls != 1 {
		t.Errorf("expected 1 FCM call, got %d", fcmCalls)
	}
}

func TestNotifier_CleansUpExpiredAPNsToken(t *testing.T) {
	apnsServer := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusGone)
	}))
	defer apnsServer.Close()

	apnsClient := newTestAPNsClient(t, apnsServer)

	store := &mockTokenStore{
		tokens: []db.DeviceToken{
			{ID: 10, HardwareID: "hw1", Token: "expired-ios", Platform: "ios"},
		},
	}

	subs := &mockSubscriberStore{
		subs: map[string]subscribers.Subscriber{
			"hw1": {Lat: 36.16, Lng: -86.78, RadiusMiles: 100},
		},
	}

	notifier := NewNotifier(apnsClient, nil, store, subs)
	defer notifier.Close()
	notifier.dispatch(200, 1, 36.16, -86.78)

	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.deleted) != 1 || store.deleted[0] != 10 {
		t.Errorf("expected token id=10 to be deleted, got %v", store.deleted)
	}
}

func TestNotifier_CleansUpUnregisteredFCMToken(t *testing.T) {
	fcmTokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "tok",
			"expires_in":   3600,
		}); err != nil {
			t.Errorf("encode token response: %v", err)
		}
	}))
	defer fcmTokenServer.Close()

	fcmSendServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		if _, err := w.Write([]byte(`{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}`)); err != nil {
			t.Errorf("write response: %v", err)
		}
	}))
	defer fcmSendServer.Close()

	fcmClient := newTestFCMClient(t, fcmTokenServer.URL, fcmSendServer.URL)

	store := &mockTokenStore{
		tokens: []db.DeviceToken{
			{ID: 20, HardwareID: "hw2", Token: "stale-android", Platform: "android"},
		},
	}

	subs := &mockSubscriberStore{
		subs: map[string]subscribers.Subscriber{
			"hw2": {Lat: 36.16, Lng: -86.78, RadiusMiles: 100},
		},
	}

	notifier := NewNotifier(nil, fcmClient, store, subs)
	defer notifier.Close()
	notifier.dispatch(300, 1, 36.16, -86.78)

	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.deleted) != 1 || store.deleted[0] != 20 {
		t.Errorf("expected token id=20 to be deleted, got %v", store.deleted)
	}
}

func TestNotifier_SkipsNilClients(t *testing.T) {
	store := &mockTokenStore{
		tokens: []db.DeviceToken{
			{ID: 1, Token: "ios-tok", Platform: "ios"},
			{ID: 2, Token: "android-tok", Platform: "android"},
		},
	}

	subs := &mockSubscriberStore{
		subs: map[string]subscribers.Subscriber{
			"hw1": {Lat: 36.16, Lng: -86.78, RadiusMiles: 100},
			"hw2": {Lat: 36.16, Lng: -86.78, RadiusMiles: 100},
		},
	}

	notifier := NewNotifier(nil, nil, store, subs)
	defer notifier.Close()
	notifier.dispatch(400, 1, 36.16, -86.78)

	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.deleted) != 0 {
		t.Errorf("expected no deletions with nil clients, got %v", store.deleted)
	}
}

func TestNotifier_EmptyTokenList(t *testing.T) {
	store := &mockTokenStore{tokens: []db.DeviceToken{}}
	notifier := NewNotifier(nil, nil, store, &mockSubscriberStore{})
	defer notifier.Close()
	notifier.dispatch(500, 1, 36.16, -86.78)
}

func TestNotifier_NotifyAsyncDoesNotBlock(t *testing.T) {
	store := &mockTokenStore{tokens: []db.DeviceToken{}}
	notifier := NewNotifier(nil, nil, store, &mockSubscriberStore{})
	defer notifier.Close()

	done := make(chan struct{})
	go func() {
		notifier.NotifyAsync(600, 1, 36.16, -86.78)
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(1 * time.Second):
		t.Fatal("NotifyAsync blocked for more than 1 second")
	}
}

func TestNotifier_FiltersBySubscriberDistance(t *testing.T) {
	var apnsCalls int

	apnsServer := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		apnsCalls++
		w.WriteHeader(http.StatusOK)
	}))
	defer apnsServer.Close()

	apnsClient := newTestAPNsClient(t, apnsServer)

	store := &mockTokenStore{
		tokens: []db.DeviceToken{
			{ID: 1, HardwareID: "nearby", Token: "nearby-ios", Platform: "ios"},
			{ID: 2, HardwareID: "far-away", Token: "far-ios", Platform: "ios"},
			{ID: 3, HardwareID: "no-sub", Token: "nosub-ios", Platform: "ios"},
		},
	}

	subs := &mockSubscriberStore{
		subs: map[string]subscribers.Subscriber{
			"nearby":   {Lat: 36.16, Lng: -86.78, RadiusMiles: 25},
			"far-away": {Lat: 40.71, Lng: -74.00, RadiusMiles: 10},
		},
	}

	notifier := NewNotifier(apnsClient, nil, store, subs)
	defer notifier.Close()
	notifier.dispatch(700, 1, 36.20, -86.80)

	if apnsCalls != 1 {
		t.Fatalf("expected 1 APNs call for the nearby subscriber, got %d", apnsCalls)
	}
}

func TestIsDuplicate_SamePlate(t *testing.T) {
	pushes := []db.SentPush{
		{PlateID: 42, Latitude: 0, Longitude: 0, SentAt: time.Now().Add(-10 * time.Minute)},
	}
	if !isDuplicate(pushes, 42, 50, 50) {
		t.Fatal("expected duplicate for same plate ID")
	}
}

func TestIsDuplicate_Proximity(t *testing.T) {
	pushes := []db.SentPush{
		{PlateID: 99, Latitude: 36.16, Longitude: -86.78, SentAt: time.Now().Add(-10 * time.Minute)},
	}
	if !isDuplicate(pushes, 100, 36.161, -86.781) {
		t.Fatal("expected duplicate for nearby location (< 1 mile)")
	}
}

func TestIsDuplicate_Cooldown(t *testing.T) {
	pushes := []db.SentPush{
		{PlateID: 99, Latitude: 0, Longitude: 0, SentAt: time.Now().Add(-1 * time.Minute)},
	}
	if !isDuplicate(pushes, 100, 50, 50) {
		t.Fatal("expected duplicate for push within 2 min cooldown")
	}
}

func TestIsDuplicate_Clear(t *testing.T) {
	pushes := []db.SentPush{
		{PlateID: 99, Latitude: 0, Longitude: 0, SentAt: time.Now().Add(-5 * time.Minute)},
	}
	if isDuplicate(pushes, 100, 50, 50) {
		t.Fatal("expected no duplicate: different plate, far location, past cooldown")
	}
}

func TestIsDuplicate_EmptyHistory(t *testing.T) {
	if isDuplicate(nil, 42, 36.16, -86.78) {
		t.Fatal("expected no duplicate with empty history")
	}
}

func TestIsDuplicate_BoundaryOneMile(t *testing.T) {
	// 1 degree latitude ≈ 69 miles, so 1/69 ≈ 0.01449 degrees ≈ 1 mile
	pushes := []db.SentPush{
		{PlateID: 99, Latitude: 36.16, Longitude: -86.78, SentAt: time.Now().Add(-10 * time.Minute)},
	}
	// ~1.5 miles away — should NOT be a duplicate
	if isDuplicate(pushes, 100, 36.16+0.022, -86.78) {
		t.Fatal("expected no duplicate for location > 1 mile away")
	}
}

func TestIsDuplicate_BoundaryCooldown(t *testing.T) {
	pushes := []db.SentPush{
		{PlateID: 99, Latitude: 0, Longitude: 0, SentAt: time.Now().Add(-2*time.Minute - time.Second)},
	}
	if isDuplicate(pushes, 100, 50, 50) {
		t.Fatal("expected no duplicate for push just past 2 min cooldown")
	}
}

func TestNotifier_SkipsDuplicatePlate(t *testing.T) {
	apnsServer := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer apnsServer.Close()
	apnsClient := newTestAPNsClient(t, apnsServer)

	store := &mockTokenStore{
		tokens: []db.DeviceToken{
			{ID: 1, HardwareID: "hw1", Token: "ios-tok", Platform: "ios"},
		},
		pushes: map[int64][]db.SentPush{
			1: {{PlateID: 42, Latitude: 0, Longitude: 0, SentAt: time.Now().Add(-10 * time.Minute)}},
		},
	}
	subs := &mockSubscriberStore{
		subs: map[string]subscribers.Subscriber{
			"hw1": {Lat: 36.16, Lng: -86.78, RadiusMiles: 100},
		},
	}

	notifier := NewNotifier(apnsClient, nil, store, subs)
	defer notifier.Close()
	notifier.dispatch(100, 42, 36.16, -86.78)

	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.recorded) != 0 {
		t.Fatalf("expected no push recorded (duplicate plate), got %d", len(store.recorded))
	}
}

func TestNotifier_SkipsDuplicateProximity(t *testing.T) {
	apnsServer := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer apnsServer.Close()
	apnsClient := newTestAPNsClient(t, apnsServer)

	store := &mockTokenStore{
		tokens: []db.DeviceToken{
			{ID: 1, HardwareID: "hw1", Token: "ios-tok", Platform: "ios"},
		},
		pushes: map[int64][]db.SentPush{
			1: {{PlateID: 99, Latitude: 36.16, Longitude: -86.78, SentAt: time.Now().Add(-10 * time.Minute)}},
		},
	}
	subs := &mockSubscriberStore{
		subs: map[string]subscribers.Subscriber{
			"hw1": {Lat: 36.16, Lng: -86.78, RadiusMiles: 100},
		},
	}

	notifier := NewNotifier(apnsClient, nil, store, subs)
	defer notifier.Close()
	notifier.dispatch(100, 50, 36.161, -86.781)

	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.recorded) != 0 {
		t.Fatalf("expected no push recorded (proximity duplicate), got %d", len(store.recorded))
	}
}

func TestNotifier_RecordsPushAfterSend(t *testing.T) {
	apnsServer := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer apnsServer.Close()
	apnsClient := newTestAPNsClient(t, apnsServer)

	store := &mockTokenStore{
		tokens: []db.DeviceToken{
			{ID: 5, HardwareID: "hw1", Token: "ios-tok", Platform: "ios"},
		},
	}
	subs := &mockSubscriberStore{
		subs: map[string]subscribers.Subscriber{
			"hw1": {Lat: 36.16, Lng: -86.78, RadiusMiles: 100},
		},
	}

	notifier := NewNotifier(apnsClient, nil, store, subs)
	defer notifier.Close()
	notifier.dispatch(100, 42, 36.16, -86.78)

	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.recorded) != 1 {
		t.Fatalf("expected 1 recorded push, got %d", len(store.recorded))
	}
	r := store.recorded[0]
	if r.DeviceTokenID != 5 {
		t.Errorf("expected device_token_id 5, got %d", r.DeviceTokenID)
	}
	if r.PlateID != 42 {
		t.Errorf("expected plate_id 42, got %d", r.PlateID)
	}
}

func newTestAPNsClient(t *testing.T, server *httptest.Server) *APNsClient {
	t.Helper()
	_, pemData := generateTestP8Key(t)
	keyFile := t.TempDir() + "/key.p8"
	if err := writeFile(keyFile, pemData); err != nil {
		t.Fatalf("write key file: %v", err)
	}

	client, err := NewAPNsClient(keyFile, "KID", "TID", "com.test.app", false)
	if err != nil {
		t.Fatalf("NewAPNsClient: %v", err)
	}
	client.endpoint = server.URL
	client.client = server.Client()
	return client
}

func newTestFCMClient(t *testing.T, tokenURL, sendURL string) *FCMClient {
	t.Helper()
	_, keyPEM := generateTestRSAKey(t)
	path := writeServiceAccount(t, "proj", "email@test.iam.gserviceaccount.com", keyPEM)

	client, err := NewFCMClient(path)
	if err != nil {
		t.Fatalf("NewFCMClient: %v", err)
	}
	client.tokenURL = tokenURL
	client.sendURL = sendURL
	return client
}
