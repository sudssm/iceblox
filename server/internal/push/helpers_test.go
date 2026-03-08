package push

import (
	"os"
	"time"
)

var fixedTime = time.Date(2026, 3, 8, 12, 0, 0, 0, time.UTC)

func writeFile(path string, data []byte) error {
	return os.WriteFile(path, data, 0600)
}
