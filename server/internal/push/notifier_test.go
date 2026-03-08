package push

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"cameras/server/internal/db"
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
		json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "tok",
			"expires_in":   3600,
		})
	}))
	defer fcmTokenServer.Close()

	fcmSendServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		fcmCalls++
		mu.Unlock()
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{}`))
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

	notifier := NewNotifier(apnsClient, fcmClient, store)
	notifier.dispatch(100)

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

	notifier := NewNotifier(apnsClient, nil, store)
	notifier.dispatch(200)

	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.deleted) != 1 || store.deleted[0] != 10 {
		t.Errorf("expected token id=10 to be deleted, got %v", store.deleted)
	}
}

func TestNotifier_CleansUpUnregisteredFCMToken(t *testing.T) {
	fcmTokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "tok",
			"expires_in":   3600,
		})
	}))
	defer fcmTokenServer.Close()

	fcmSendServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte(`{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}`))
	}))
	defer fcmSendServer.Close()

	fcmClient := newTestFCMClient(t, fcmTokenServer.URL, fcmSendServer.URL)

	store := &mockTokenStore{
		tokens: []db.DeviceToken{
			{ID: 20, HardwareID: "hw2", Token: "stale-android", Platform: "android"},
		},
	}

	notifier := NewNotifier(nil, fcmClient, store)
	notifier.dispatch(300)

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

	notifier := NewNotifier(nil, nil, store)
	notifier.dispatch(400)

	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.deleted) != 0 {
		t.Errorf("expected no deletions with nil clients, got %v", store.deleted)
	}
}

func TestNotifier_EmptyTokenList(t *testing.T) {
	store := &mockTokenStore{tokens: []db.DeviceToken{}}
	notifier := NewNotifier(nil, nil, store)
	notifier.dispatch(500)
}

func TestNotifier_NotifyAsyncDoesNotBlock(t *testing.T) {
	store := &mockTokenStore{tokens: []db.DeviceToken{}}
	notifier := NewNotifier(nil, nil, store)

	done := make(chan struct{})
	go func() {
		notifier.NotifyAsync(600)
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(1 * time.Second):
		t.Fatal("NotifyAsync blocked for more than 1 second")
	}
}

func newTestAPNsClient(t *testing.T, server *httptest.Server) *APNsClient {
	t.Helper()
	_, pemData := generateTestP8Key(t)
	keyFile := t.TempDir() + "/key.p8"
	writeFile(keyFile, pemData)

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
