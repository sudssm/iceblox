package push

import (
	"bytes"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	// #nosec G101 -- OAuth token endpoint URL, not a hardcoded credential.
	fcmTokenURL      = "https://oauth2.googleapis.com/token"
	fcmTokenLifetime = 55 * time.Minute
)

// ErrFCMTokenExpired is returned when FCM indicates the device token
// is no longer registered.
var ErrFCMTokenExpired = fmt.Errorf("fcm: device token unregistered")

type serviceAccount struct {
	ProjectID   string `json:"project_id"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
}

type FCMClient struct {
	client      *http.Client
	key         *rsa.PrivateKey
	projectID   string
	clientEmail string
	tokenURL    string
	sendURL     string

	mu          sync.Mutex
	cachedToken string
	tokenExpiry time.Time
}

func NewFCMClient(serviceAccountFile string) (*FCMClient, error) {
	data, err := os.ReadFile(serviceAccountFile)
	if err != nil {
		return nil, fmt.Errorf("fcm: read service account: %w", err)
	}

	var sa serviceAccount
	if err := json.Unmarshal(data, &sa); err != nil {
		return nil, fmt.Errorf("fcm: parse service account: %w", err)
	}

	if sa.ProjectID == "" || sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, fmt.Errorf("fcm: service account missing required fields")
	}

	key, err := parseRSAKey(sa.PrivateKey)
	if err != nil {
		return nil, fmt.Errorf("fcm: parse private key: %w", err)
	}

	return &FCMClient{
		client:      &http.Client{Timeout: 30 * time.Second},
		key:         key,
		projectID:   sa.ProjectID,
		clientEmail: sa.ClientEmail,
		tokenURL:    fcmTokenURL,
		sendURL:     fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", sa.ProjectID),
	}, nil
}

func parseRSAKey(keyPEM string) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(keyPEM))
	if block == nil {
		return nil, fmt.Errorf("no PEM block found")
	}

	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse PKCS8: %w", err)
	}

	key, ok := parsed.(*rsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("key is not RSA")
	}
	return key, nil
}

func (c *FCMClient) getAccessToken() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.cachedToken != "" && time.Now().Before(c.tokenExpiry) {
		return c.cachedToken, nil
	}

	now := time.Now()
	claims := map[string]interface{}{
		"iss":   c.clientEmail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   c.tokenURL,
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	}

	jwt, err := signRS256JWT(c.key, claims)
	if err != nil {
		return "", fmt.Errorf("fcm: sign jwt: %w", err)
	}

	token, expiry, err := c.exchangeToken(jwt)
	if err != nil {
		return "", err
	}

	c.cachedToken = token
	c.tokenExpiry = expiry
	return token, nil
}

func (c *FCMClient) exchangeToken(jwt string) (string, time.Time, error) {
	form := url.Values{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {jwt},
	}

	resp, err := c.client.Post(c.tokenURL, "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if err != nil {
		return "", time.Time{}, fmt.Errorf("fcm: token exchange: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", time.Time{}, fmt.Errorf("fcm: token exchange status %d: %s", resp.StatusCode, string(body))
	}

	var tokenResp struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
		return "", time.Time{}, fmt.Errorf("fcm: decode token response: %w", err)
	}

	expiry := time.Now().Add(fcmTokenLifetime)
	return tokenResp.AccessToken, expiry, nil
}

// Send sends a data-only message to an Android device via FCM.
func (c *FCMClient) Send(deviceToken string, data map[string]string) error {
	accessToken, err := c.getAccessToken()
	if err != nil {
		return err
	}

	message := map[string]interface{}{
		"message": map[string]interface{}{
			"token": deviceToken,
			"data":  data,
		},
	}

	payload, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("fcm: marshal message: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, c.sendURL, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("fcm: new request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("fcm: send: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return nil
	}

	respBody, _ := io.ReadAll(resp.Body)

	if isUnregisteredError(respBody) {
		return ErrFCMTokenExpired
	}

	return fmt.Errorf("fcm: unexpected status %d: %s", resp.StatusCode, string(respBody))
}

func isUnregisteredError(body []byte) bool {
	var errResp struct {
		Error struct {
			Details []struct {
				ErrorCode string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(body, &errResp); err != nil {
		return false
	}
	for _, d := range errResp.Error.Details {
		if d.ErrorCode == "UNREGISTERED" {
			return true
		}
	}
	return false
}
