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
	mu      sync.Mutex
	tokens  []db.DeviceToken
	deleted []int64
	err     error
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
	notifier.dispatch(100, 36.16, -86.78)

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
	notifier.dispatch(200, 36.16, -86.78)

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
	notifier.dispatch(300, 36.16, -86.78)

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
	notifier.dispatch(400, 36.16, -86.78)

	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.deleted) != 0 {
		t.Errorf("expected no deletions with nil clients, got %v", store.deleted)
	}
}

func TestNotifier_EmptyTokenList(t *testing.T) {
	store := &mockTokenStore{tokens: []db.DeviceToken{}}
	notifier := NewNotifier(nil, nil, store, &mockSubscriberStore{})
	notifier.dispatch(500, 36.16, -86.78)
}

func TestNotifier_NotifyAsyncDoesNotBlock(t *testing.T) {
	store := &mockTokenStore{tokens: []db.DeviceToken{}}
	notifier := NewNotifier(nil, nil, store, &mockSubscriberStore{})

	done := make(chan struct{})
	go func() {
		notifier.NotifyAsync(600, 36.16, -86.78)
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
	notifier.dispatch(700, 36.20, -86.80)

	if apnsCalls != 1 {
		t.Fatalf("expected 1 APNs call for the nearby subscriber, got %d", apnsCalls)
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
