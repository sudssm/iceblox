package push

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"testing"
)

func generateTestP8Key(t *testing.T) (*ecdsa.PrivateKey, []byte) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("marshal key: %v", err)
	}
	pemData := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	return key, pemData
}

func TestParseP8Key(t *testing.T) {
	_, pemData := generateTestP8Key(t)

	key, err := parseP8Key(pemData)
	if err != nil {
		t.Fatalf("parseP8Key: %v", err)
	}
	if key == nil {
		t.Fatal("expected non-nil key")
	}
}

func TestParseP8Key_InvalidPEM(t *testing.T) {
	_, err := parseP8Key([]byte("not a pem block"))
	if err == nil {
		t.Fatal("expected error for invalid PEM")
	}
}

func TestAPNsJWTGeneration(t *testing.T) {
	key, _ := generateTestP8Key(t)

	token, err := signES256JWT(key, "KEYID123", "TEAMID456", fixedTime)
	if err != nil {
		t.Fatalf("signES256JWT: %v", err)
	}

	claims, err := verifyES256JWT(token, key)
	if err != nil {
		t.Fatalf("verifyES256JWT: %v", err)
	}

	if claims["iss"] != "TEAMID456" {
		t.Errorf("expected iss TEAMID456, got %v", claims["iss"])
	}
	if int64(claims["iat"].(float64)) != fixedTime.Unix() {
		t.Errorf("expected iat %d, got %v", fixedTime.Unix(), claims["iat"])
	}
}

func TestAPNsJWTCaching(t *testing.T) {
	key, pemData := generateTestP8Key(t)
	_ = key

	keyFile := t.TempDir() + "/key.p8"
	if err := writeFile(keyFile, pemData); err != nil {
		t.Fatalf("write key file: %v", err)
	}

	client, err := NewAPNsClient(keyFile, "KID", "TID", "com.test.app", false)
	if err != nil {
		t.Fatalf("NewAPNsClient: %v", err)
	}

	jwt1, err := client.getJWT()
	if err != nil {
		t.Fatalf("first getJWT: %v", err)
	}

	jwt2, err := client.getJWT()
	if err != nil {
		t.Fatalf("second getJWT: %v", err)
	}

	if jwt1 != jwt2 {
		t.Error("expected cached JWT to be returned on second call")
	}
}

func TestAPNsSendNotification_Success(t *testing.T) {
	var receivedBody map[string]interface{}
	var receivedHeaders http.Header

	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedHeaders = r.Header
		json.NewDecoder(r.Body).Decode(&receivedBody)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	_, pemData := generateTestP8Key(t)
	keyFile := t.TempDir() + "/key.p8"
	writeFile(keyFile, pemData)

	client, err := NewAPNsClient(keyFile, "KID", "TID", "com.test.app", false)
	if err != nil {
		t.Fatalf("NewAPNsClient: %v", err)
	}
	client.endpoint = server.URL
	client.client = server.Client()

	err = client.SendNotification("device-token-abc", "Target Detected", "A target plate was detected", map[string]string{
		"sighting_id": "123",
	})
	if err != nil {
		t.Fatalf("SendNotification: %v", err)
	}

	if receivedHeaders.Get("apns-topic") != "com.test.app" {
		t.Errorf("expected apns-topic com.test.app, got %s", receivedHeaders.Get("apns-topic"))
	}
	if receivedHeaders.Get("apns-push-type") != "alert" {
		t.Errorf("expected apns-push-type alert, got %s", receivedHeaders.Get("apns-push-type"))
	}
	if receivedHeaders.Get("apns-priority") != "10" {
		t.Errorf("expected apns-priority 10, got %s", receivedHeaders.Get("apns-priority"))
	}

	aps, ok := receivedBody["aps"].(map[string]interface{})
	if !ok {
		t.Fatal("expected aps in payload")
	}
	alert, ok := aps["alert"].(map[string]interface{})
	if !ok {
		t.Fatal("expected alert in aps")
	}
	if alert["title"] != "Target Detected" {
		t.Errorf("expected title 'Target Detected', got %v", alert["title"])
	}
	if receivedBody["sighting_id"] != "123" {
		t.Errorf("expected sighting_id 123, got %v", receivedBody["sighting_id"])
	}
}

func TestAPNsSendNotification_GoneReturnsExpiredError(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusGone)
	}))
	defer server.Close()

	_, pemData := generateTestP8Key(t)
	keyFile := t.TempDir() + "/key.p8"
	writeFile(keyFile, pemData)

	client, err := NewAPNsClient(keyFile, "KID", "TID", "com.test.app", false)
	if err != nil {
		t.Fatalf("NewAPNsClient: %v", err)
	}
	client.endpoint = server.URL
	client.client = server.Client()

	err = client.SendNotification("expired-token", "Title", "Body", nil)
	if err != ErrAPNsTokenExpired {
		t.Fatalf("expected ErrAPNsTokenExpired, got %v", err)
	}
}

func TestNewAPNsClient_MissingKeyFile(t *testing.T) {
	_, err := NewAPNsClient("/nonexistent/key.p8", "KID", "TID", "com.test.app", false)
	if err == nil {
		t.Fatal("expected error for missing key file")
	}
}
