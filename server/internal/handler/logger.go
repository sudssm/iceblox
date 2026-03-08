package handler

import (
	"encoding/json"
	"os"
	"sync"
)

type PlateLogEntry struct {
	PlateHash  string  `json:"plate_hash"`
	Latitude   float64 `json:"latitude"`
	Longitude  float64 `json:"longitude"`
	ReceivedAt string  `json:"received_at"`
	Matched    bool    `json:"matched"`
}

type LogWriter interface {
	WriteEntry(entry PlateLogEntry) error
}

type JSONLLogger struct {
	mu   sync.Mutex
	file *os.File
}

func NewJSONLLogger(path string) (*JSONLLogger, error) {
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return nil, err
	}
	return &JSONLLogger{file: f}, nil
}

func (l *JSONLLogger) WriteEntry(entry PlateLogEntry) error {
	l.mu.Lock()
	defer l.mu.Unlock()

	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	_, err = l.file.Write(data)
	return err
}

func (l *JSONLLogger) Close() error {
	return l.file.Close()
}
