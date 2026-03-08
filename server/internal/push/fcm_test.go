package push

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func generateTestRSAKey(t *testing.T) (*rsa.PrivateKey, string) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate rsa key: %v", err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("marshal key: %v", err)
	}
	pemData := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	return key, string(pemData)
}

func writeServiceAccount(t *testing.T, projectID, email, keyPEM string) string {
	t.Helper()
	sa := map[string]string{
		"project_id":   projectID,
		"client_email": email,
		"private_key":  keyPEM,
	}
	data, err := json.Marshal(sa)
	if err != nil {
		t.Fatalf("marshal service account: %v", err)
	}
	path := filepath.Join(t.TempDir(), "sa.json")
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatalf("write service account: %v", err)
	}
	return path
}

func TestNewFCMClient(t *testing.T) {
	_, keyPEM := generateTestRSAKey(t)
	path := writeServiceAccount(t, "my-project", "test@test.iam.gserviceaccount.com", keyPEM)

	client, err := NewFCMClient(path)
	if err != nil {
		t.Fatalf("NewFCMClient: %v", err)
	}
	if client.projectID != "my-project" {
		t.Errorf("expected project_id my-project, got %s", client.projectID)
	}
}

func TestNewFCMClient_MissingFile(t *testing.T) {
	_, err := NewFCMClient("/nonexistent/sa.json")
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestNewFCMClient_MissingFields(t *testing.T) {
	data := `{"project_id":"","client_email":"","private_key":""}`
	path := filepath.Join(t.TempDir(), "sa.json")
	if err := os.WriteFile(path, []byte(data), 0600); err != nil {
		t.Fatalf("write service account: %v", err)
	}

	_, err := NewFCMClient(path)
	if err == nil {
		t.Fatal("expected error for missing fields")
	}
}

func TestFCMTokenExchange(t *testing.T) {
	_, keyPEM := generateTestRSAKey(t)

	tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("expected POST, got %s", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "test-access-token",
			"expires_in":   3600,
		}); err != nil {
			t.Errorf("encode token response: %v", err)
		}
	}))
	defer tokenServer.Close()

	path := writeServiceAccount(t, "my-project", "test@test.iam.gserviceaccount.com", keyPEM)
	client, err := NewFCMClient(path)
	if err != nil {
		t.Fatalf("NewFCMClient: %v", err)
	}
	client.tokenURL = tokenServer.URL

	token, err := client.getAccessToken()
	if err != nil {
		t.Fatalf("getAccessToken: %v", err)
	}
	if token != "test-access-token" {
		t.Errorf("expected test-access-token, got %s", token)
	}
}

func TestFCMTokenCaching(t *testing.T) {
	_, keyPEM := generateTestRSAKey(t)

	callCount := 0
	tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "cached-token",
			"expires_in":   3600,
		}); err != nil {
			t.Errorf("encode token response: %v", err)
		}
	}))
	defer tokenServer.Close()

	path := writeServiceAccount(t, "proj", "email@test.iam.gserviceaccount.com", keyPEM)
	client, err := NewFCMClient(path)
	if err != nil {
		t.Fatalf("NewFCMClient: %v", err)
	}
	client.tokenURL = tokenServer.URL

	if _, err := client.getAccessToken(); err != nil {
		t.Fatalf("first getAccessToken: %v", err)
	}
	if _, err := client.getAccessToken(); err != nil {
		t.Fatalf("second getAccessToken: %v", err)
	}

	if callCount != 1 {
		t.Errorf("expected 1 token exchange call (cached), got %d", callCount)
	}
}

func TestFCMSend_Success(t *testing.T) {
	_, keyPEM := generateTestRSAKey(t)

	tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "access-tok",
			"expires_in":   3600,
		}); err != nil {
			t.Errorf("encode token response: %v", err)
		}
	}))
	defer tokenServer.Close()

	var sentPayload map[string]interface{}
	fcmServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&sentPayload); err != nil {
			t.Errorf("decode send payload: %v", err)
		}
		w.WriteHeader(http.StatusOK)
		if _, err := w.Write([]byte(`{}`)); err != nil {
			t.Errorf("write response: %v", err)
		}
	}))
	defer fcmServer.Close()

	path := writeServiceAccount(t, "proj", "email@test.iam.gserviceaccount.com", keyPEM)
	client, err := NewFCMClient(path)
	if err != nil {
		t.Fatalf("NewFCMClient: %v", err)
	}
	client.tokenURL = tokenServer.URL
	client.sendURL = fcmServer.URL

	err = client.Send("device-token-123", map[string]string{
		"sighting_id": "456",
		"title":       "Target Detected",
		"body":        "A target plate was detected",
	})
	if err != nil {
		t.Fatalf("Send: %v", err)
	}

	msg, ok := sentPayload["message"].(map[string]interface{})
	if !ok {
		t.Fatal("expected message in payload")
	}
	if msg["token"] != "device-token-123" {
		t.Errorf("expected token device-token-123, got %v", msg["token"])
	}
	data, ok := msg["data"].(map[string]interface{})
	if !ok {
		t.Fatal("expected data in message")
	}
	if data["sighting_id"] != "456" {
		t.Errorf("expected sighting_id 456, got %v", data["sighting_id"])
	}
}

func TestFCMSend_UnregisteredError(t *testing.T) {
	_, keyPEM := generateTestRSAKey(t)

	tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "tok",
			"expires_in":   3600,
		}); err != nil {
			t.Errorf("encode token response: %v", err)
		}
	}))
	defer tokenServer.Close()

	fcmServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		if _, err := w.Write([]byte(`{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}`)); err != nil {
			t.Errorf("write response: %v", err)
		}
	}))
	defer fcmServer.Close()

	path := writeServiceAccount(t, "proj", "email@test.iam.gserviceaccount.com", keyPEM)
	client, err := NewFCMClient(path)
	if err != nil {
		t.Fatalf("NewFCMClient: %v", err)
	}
	client.tokenURL = tokenServer.URL
	client.sendURL = fcmServer.URL

	err = client.Send("stale-token", map[string]string{"sighting_id": "1"})
	if err != ErrFCMTokenExpired {
		t.Fatalf("expected ErrFCMTokenExpired, got %v", err)
	}
}

func TestIsUnregisteredError(t *testing.T) {
	tests := []struct {
		name     string
		body     string
		expected bool
	}{
		{
			"unregistered",
			`{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}`,
			true,
		},
		{
			"other error",
			`{"error":{"details":[{"errorCode":"INTERNAL"}]}}`,
			false,
		},
		{
			"invalid json",
			`not json`,
			false,
		},
		{
			"empty",
			`{}`,
			false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := isUnregisteredError([]byte(tt.body))
			if result != tt.expected {
				t.Errorf("expected %v, got %v", tt.expected, result)
			}
		})
	}
}

func TestRS256JWTClaims(t *testing.T) {
	key, _ := generateTestRSAKey(t)

	claims := map[string]interface{}{
		"iss":   "test@test.iam.gserviceaccount.com",
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   "https://oauth2.googleapis.com/token",
		"iat":   fixedTime.Unix(),
		"exp":   fixedTime.Add(time.Hour).Unix(),
	}

	token, err := signRS256JWT(key, claims)
	if err != nil {
		t.Fatalf("signRS256JWT: %v", err)
	}

	decoded, err := decodeJWTClaims(token)
	if err != nil {
		t.Fatalf("decodeJWTClaims: %v", err)
	}

	if decoded["iss"] != "test@test.iam.gserviceaccount.com" {
		t.Errorf("expected iss, got %v", decoded["iss"])
	}
	if decoded["scope"] != "https://www.googleapis.com/auth/firebase.messaging" {
		t.Errorf("expected scope, got %v", decoded["scope"])
	}
}
