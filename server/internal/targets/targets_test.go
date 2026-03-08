package targets

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
)

func hmacHash(plate string, pepper []byte) string {
	mac := hmac.New(sha256.New, pepper)
	mac.Write([]byte(plate))
	return hex.EncodeToString(mac.Sum(nil))
}

func writePlatesFile(t *testing.T, plates []string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "plates.txt")
	content := ""
	for _, p := range plates {
		content += p + "\n"
	}
	os.WriteFile(path, []byte(content), 0644)
	return path
}

func TestNew_LoadsPlates(t *testing.T) {
	path := writePlatesFile(t, []string{"ABC123", "XYZ789"})
	pepper := []byte("test-pepper")

	store, err := New(path, pepper)
	if err != nil {
		t.Fatalf("New() error: %v", err)
	}

	if store.Count() != 2 {
		t.Fatalf("expected 2 targets, got %d", store.Count())
	}

	h := hmacHash("ABC123", pepper)
	if !store.Contains(h) {
		t.Error("expected ABC123 hash to be found")
	}

	h = hmacHash("XYZ789", pepper)
	if !store.Contains(h) {
		t.Error("expected XYZ789 hash to be found")
	}

	h = hmacHash("NOTFOUND", pepper)
	if store.Contains(h) {
		t.Error("expected NOTFOUND hash to not be found")
	}
}

func TestNew_NormalizesPlates(t *testing.T) {
	path := writePlatesFile(t, []string{"abc 123", "x-y-z"})
	pepper := []byte("test-pepper")

	store, err := New(path, pepper)
	if err != nil {
		t.Fatalf("New() error: %v", err)
	}

	h := hmacHash("ABC123", pepper)
	if !store.Contains(h) {
		t.Errorf("expected normalized 'abc 123' -> 'ABC123' to match")
	}

	h = hmacHash("XYZ", pepper)
	if !store.Contains(h) {
		t.Errorf("expected normalized 'x-y-z' -> 'XYZ' to match")
	}
}

func TestNew_SkipsEmptyLines(t *testing.T) {
	path := writePlatesFile(t, []string{"ABC123", "", "  ", "XYZ789"})
	pepper := []byte("test-pepper")

	store, err := New(path, pepper)
	if err != nil {
		t.Fatalf("New() error: %v", err)
	}

	if store.Count() != 2 {
		t.Fatalf("expected 2 targets (skipping empty lines), got %d", store.Count())
	}
}

func TestReload(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "plates.txt")
	pepper := []byte("test-pepper")

	os.WriteFile(path, []byte("ABC123\n"), 0644)
	store, err := New(path, pepper)
	if err != nil {
		t.Fatalf("New() error: %v", err)
	}

	if store.Count() != 1 {
		t.Fatalf("expected 1 target, got %d", store.Count())
	}

	os.WriteFile(path, []byte("ABC123\nXYZ789\nDEF456\n"), 0644)
	if err := store.Reload(); err != nil {
		t.Fatalf("Reload() error: %v", err)
	}

	if store.Count() != 3 {
		t.Fatalf("expected 3 targets after reload, got %d", store.Count())
	}
}

func TestNew_FileNotFound(t *testing.T) {
	_, err := New("/nonexistent/plates.txt", []byte("pepper"))
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}
