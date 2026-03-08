package targets

import (
	"bufio"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
)

type Store struct {
	mu     sync.RWMutex
	hashes map[string]bool
	path   string
	pepper []byte
}

func New(path string, pepper []byte) (*Store, error) {
	s := &Store{path: path, pepper: pepper}
	if err := s.load(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Store) Contains(hash string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.hashes[hash]
}

func (s *Store) Count() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.hashes)
}

func (s *Store) Reload() error {
	return s.load()
}

func (s *Store) load() error {
	f, err := os.Open(s.path)
	if err != nil {
		return fmt.Errorf("open plates file: %w", err)
	}
	defer f.Close()

	hashes := make(map[string]bool)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		plate := normalize(scanner.Text())
		if plate == "" {
			continue
		}
		h := computeHMAC(plate, s.pepper)
		hashes[h] = true
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("read plates file: %w", err)
	}

	s.mu.Lock()
	s.hashes = hashes
	s.mu.Unlock()

	log.Printf("loaded %d target plates from %s", len(hashes), s.path)
	return nil
}

func normalize(plate string) string {
	plate = strings.ToUpper(plate)
	plate = strings.Map(func(r rune) rune {
		if r == ' ' || r == '-' {
			return -1
		}
		return r
	}, plate)
	return strings.TrimSpace(plate)
}

func computeHMAC(plate string, pepper []byte) string {
	mac := hmac.New(sha256.New, pepper)
	mac.Write([]byte(plate))
	return hex.EncodeToString(mac.Sum(nil))
}
