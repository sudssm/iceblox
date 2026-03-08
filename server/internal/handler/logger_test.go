package handler

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestJSONLLogger_WritesEntries(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.jsonl")

	logger, err := NewJSONLLogger(path)
	if err != nil {
		t.Fatalf("failed to create logger: %v", err)
	}

	entries := []PlateLogEntry{
		{PlateHash: "aabb", Latitude: 1.0, Longitude: 2.0, ReceivedAt: "2026-01-01T00:00:00Z"},
		{PlateHash: "ccdd", Latitude: 3.0, Longitude: 4.0, ReceivedAt: "2026-01-01T00:01:00Z"},
	}

	for _, e := range entries {
		if err := logger.WriteEntry(e); err != nil {
			t.Fatalf("WriteEntry failed: %v", err)
		}
	}
	if err := logger.Close(); err != nil {
		t.Fatalf("failed to close logger: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read log file: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 lines, got %d", len(lines))
	}

	var parsed PlateLogEntry
	if err := json.Unmarshal([]byte(lines[0]), &parsed); err != nil {
		t.Fatalf("failed to unmarshal log entry: %v", err)
	}
	if parsed.PlateHash != "aabb" {
		t.Errorf("expected aabb, got %s", parsed.PlateHash)
	}
}

func TestJSONLLogger_AppendsToExisting(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.jsonl")

	if err := os.WriteFile(path, []byte(`{"existing":"line"}`+"\n"), 0644); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	logger, err := NewJSONLLogger(path)
	if err != nil {
		t.Fatalf("failed to create logger: %v", err)
	}

	if err := logger.WriteEntry(PlateLogEntry{PlateHash: "new", ReceivedAt: "2026-01-01T00:00:00Z"}); err != nil {
		t.Fatalf("WriteEntry failed: %v", err)
	}
	if err := logger.Close(); err != nil {
		t.Fatalf("failed to close logger: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read log file: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 lines (existing + new), got %d", len(lines))
	}
}
