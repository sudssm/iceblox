package push

import (
	"bytes"
	"crypto"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"time"
)

func signES256JWT(key *ecdsa.PrivateKey, keyID, teamID string, now time.Time) (string, error) {
	header := map[string]string{
		"alg": "ES256",
		"kid": keyID,
	}
	claims := map[string]interface{}{
		"iss": teamID,
		"iat": now.Unix(),
	}
	return signJWT(header, claims, func(signingInput []byte) ([]byte, error) {
		hash := sha256.Sum256(signingInput)
		r, s, err := ecdsa.Sign(rand.Reader, key, hash[:])
		if err != nil {
			return nil, err
		}
		// ES256 signature is r || s, each padded to 32 bytes
		curveBits := key.Curve.Params().BitSize
		keyBytes := curveBits / 8
		rBytes := r.Bytes()
		sBytes := s.Bytes()
		sig := make([]byte, 2*keyBytes)
		copy(sig[keyBytes-len(rBytes):keyBytes], rBytes)
		copy(sig[2*keyBytes-len(sBytes):], sBytes)
		return sig, nil
	})
}

func signRS256JWT(key *rsa.PrivateKey, claims map[string]interface{}) (string, error) {
	header := map[string]string{
		"alg": "RS256",
		"typ": "JWT",
	}
	return signJWT(header, claims, func(signingInput []byte) ([]byte, error) {
		hash := sha256.Sum256(signingInput)
		return rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, hash[:])
	})
}

func signJWT(header map[string]string, claims map[string]interface{}, sign func([]byte) ([]byte, error)) (string, error) {
	headerJSON, err := json.Marshal(header)
	if err != nil {
		return "", fmt.Errorf("marshal header: %w", err)
	}
	claimsJSON, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("marshal claims: %w", err)
	}

	headerB64 := base64.RawURLEncoding.EncodeToString(headerJSON)
	claimsB64 := base64.RawURLEncoding.EncodeToString(claimsJSON)
	signingInput := []byte(headerB64 + "." + claimsB64)

	sig, err := sign(signingInput)
	if err != nil {
		return "", fmt.Errorf("sign: %w", err)
	}

	sigB64 := base64.RawURLEncoding.EncodeToString(sig)
	return headerB64 + "." + claimsB64 + "." + sigB64, nil
}

// verifyES256JWT verifies an ES256-signed JWT and returns the claims.
// Used for testing.
func verifyES256JWT(token string, key *ecdsa.PrivateKey) (map[string]interface{}, error) {
	parts := splitJWT(token)
	if parts == nil {
		return nil, fmt.Errorf("invalid JWT format")
	}

	signingInput := []byte(parts[0] + "." + parts[1])
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return nil, fmt.Errorf("decode signature: %w", err)
	}

	hash := sha256.Sum256(signingInput)

	curveBits := key.Curve.Params().BitSize
	keyBytes := curveBits / 8
	if len(sig) != 2*keyBytes {
		return nil, fmt.Errorf("invalid signature length")
	}
	r := new(big.Int).SetBytes(sig[:keyBytes])
	s := new(big.Int).SetBytes(sig[keyBytes:])

	if !ecdsa.Verify(&key.PublicKey, hash[:], r, s) {
		return nil, fmt.Errorf("signature verification failed")
	}

	claimsJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("decode claims: %w", err)
	}

	var claims map[string]interface{}
	if err := json.Unmarshal(claimsJSON, &claims); err != nil {
		return nil, fmt.Errorf("unmarshal claims: %w", err)
	}
	return claims, nil
}

func splitJWT(token string) []string {
	var parts []string
	start := 0
	count := 0
	for i, c := range token {
		if c == '.' {
			parts = append(parts, token[start:i])
			start = i + 1
			count++
		}
	}
	parts = append(parts, token[start:])
	if len(parts) != 3 {
		return nil
	}
	return parts
}

func readerFromBytes(b []byte) io.Reader {
	return bytes.NewReader(b)
}

// decodeJWTClaims extracts the claims from a JWT without verification.
func decodeJWTClaims(token string) (map[string]interface{}, error) {
	parts := splitJWT(token)
	if parts == nil {
		return nil, fmt.Errorf("invalid JWT format")
	}
	claimsJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("decode claims: %w", err)
	}
	var claims map[string]interface{}
	if err := json.Unmarshal(claimsJSON, &claims); err != nil {
		return nil, fmt.Errorf("unmarshal claims: %w", err)
	}
	return claims, nil
}
