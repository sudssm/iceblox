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

type Record struct {
	Plate string
	Hash  string
}

type Store struct {
	mu      sync.RWMutex
	hashes  map[string]int64  // hash → plate_id (0 until DB sync)
	plates  map[string]string // hash → plaintext plate
	records []Record
	path    string
	pepper  []byte
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
	_, ok := s.hashes[hash]
	return ok
}

func (s *Store) PlateID(hash string) (int64, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	id, ok := s.hashes[hash]
	return id, ok
}

func (s *Store) Plate(hash string) (string, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	plate, ok := s.plates[hash]
	return plate, ok
}

func (s *Store) Count() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.hashes)
}

func (s *Store) Records() []Record {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Record, len(s.records))
	copy(out, s.records)
	return out
}

func (s *Store) SetPlateIDs(mapping map[string]int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for hash, id := range mapping {
		if _, ok := s.hashes[hash]; ok {
			s.hashes[hash] = id
		}
	}
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

	hashes := make(map[string]int64)
	plates := make(map[string]string)
	var records []Record
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		plate := normalize(scanner.Text())
		if plate == "" {
			continue
		}
		h := computeHMAC(plate, s.pepper)
		hashes[h] = 0
		plates[h] = plate
		records = append(records, Record{Plate: plate, Hash: h})
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("read plates file: %w", err)
	}

	s.mu.Lock()
	s.hashes = hashes
	s.plates = plates
	s.records = records
	s.mu.Unlock()

	log.Printf("loaded %d target plates from %s", len(hashes), s.path)
	return nil
}

func normalize(plate string) string {
	plate = strings.ToUpper(plate)
	plate = strings.Map(func(r rune) rune {
		// Keep only ASCII alphanumeric (overview spec: "ASCII only")
		if (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			return r
		}
		return -1
	}, plate)
	return strings.TrimSpace(plate)
}

func computeHMAC(plate string, pepper []byte) string {
	mac := hmac.New(sha256.New, pepper)
	mac.Write([]byte(plate))
	return hex.EncodeToString(mac.Sum(nil))
}
