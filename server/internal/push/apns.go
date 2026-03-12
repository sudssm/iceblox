package push

import (
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

const (
	apnsDevEndpoint  = "https://api.development.push.apple.com"
	apnsProdEndpoint = "https://api.push.apple.com"
	apnsJWTLifetime  = 50 * time.Minute
)

// ErrAPNsTokenExpired is returned when APNs responds with HTTP 410,
// indicating the device token is no longer valid.
var ErrAPNsTokenExpired = fmt.Errorf("apns: device token expired")

type APNsClient struct {
	client   *http.Client
	key      *ecdsa.PrivateKey
	keyID    string
	teamID   string
	bundleID string
	endpoint string

	mu         sync.Mutex
	cachedJWT  string
	jwtExpires time.Time
}

func NewAPNsClient(keyData []byte, keyID, teamID, bundleID string, production bool) (*APNsClient, error) {
	key, err := parseP8Key(keyData)
	if err != nil {
		return nil, fmt.Errorf("apns: parse key: %w", err)
	}

	endpoint := apnsDevEndpoint
	if production {
		endpoint = apnsProdEndpoint
	}

	return &APNsClient{
		client:   &http.Client{Timeout: 30 * time.Second},
		key:      key,
		keyID:    keyID,
		teamID:   teamID,
		bundleID: bundleID,
		endpoint: endpoint,
	}, nil
}

func parseP8Key(data []byte) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode(data)
	if block == nil {
		return nil, fmt.Errorf("no PEM block found")
	}

	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse PKCS8: %w", err)
	}

	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("key is not ECDSA")
	}
	return key, nil
}

func (c *APNsClient) getJWT() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.cachedJWT != "" && time.Now().Before(c.jwtExpires) {
		return c.cachedJWT, nil
	}

	now := time.Now()
	token, err := signES256JWT(c.key, c.keyID, c.teamID, now)
	if err != nil {
		return "", err
	}

	c.cachedJWT = token
	c.jwtExpires = now.Add(apnsJWTLifetime)
	return token, nil
}

// SendNotification sends an alert notification to an iOS device.
func (c *APNsClient) SendNotification(deviceToken, title, body string, data map[string]string) error {
	payload := map[string]interface{}{
		"aps": map[string]interface{}{
			"alert": map[string]string{
				"title": title,
				"body":  body,
			},
		},
	}
	for k, v := range data {
		payload[k] = v
	}

	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("apns: marshal payload: %w", err)
	}

	return c.send(deviceToken, payloadBytes)
}

func (c *APNsClient) send(deviceToken string, payload []byte) error {
	jwt, err := c.getJWT()
	if err != nil {
		return fmt.Errorf("apns: get jwt: %w", err)
	}

	url := fmt.Sprintf("%s/3/device/%s", c.endpoint, deviceToken)
	req, err := http.NewRequest(http.MethodPost, url, io.NopCloser(
		readerFromBytes(payload)))
	if err != nil {
		return fmt.Errorf("apns: new request: %w", err)
	}

	req.Header.Set("authorization", "bearer "+jwt)
	req.Header.Set("apns-topic", c.bundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("apns: send: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusGone {
		return ErrAPNsTokenExpired
	}

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("apns: unexpected status %d: %s", resp.StatusCode, string(respBody))
	}

	return nil
}
