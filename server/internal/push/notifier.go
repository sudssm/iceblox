package push

import (
	"context"
	"fmt"
	"log"
	"time"

	"iceblox/server/internal/db"
	"iceblox/server/internal/geo"
	"iceblox/server/internal/subscribers"
)

// TokenStore provides access to device tokens for push notifications.
type TokenStore interface {
	AllDeviceTokens(ctx context.Context) ([]db.DeviceToken, error)
	DeleteDeviceToken(ctx context.Context, id int64) error
	RecentPushesForDevice(ctx context.Context, deviceTokenID int64) ([]db.SentPush, error)
	RecordSentPush(ctx context.Context, deviceTokenID, plateID int64, lat, lng float64) error
	CleanupStalePushes(ctx context.Context, staleThreshold time.Duration) (int64, error)
}

type SubscriberStore interface {
	All() map[string]subscribers.Subscriber
}

// Notifier dispatches push notifications to registered devices with active
// proximity subscriptions that cover the matched sighting.
type Notifier struct {
	apns  *APNsClient
	fcm   *FCMClient
	store TokenStore
	subs  SubscriberStore
	done  chan struct{}
}

// NewNotifier creates a Notifier. Both apns and fcm may be nil if not configured.
func NewNotifier(apns *APNsClient, fcm *FCMClient, store TokenStore, subs SubscriberStore) *Notifier {
	n := &Notifier{
		apns:  apns,
		fcm:   fcm,
		store: store,
		subs:  subs,
		done:  make(chan struct{}),
	}
	go n.cleanupLoop()
	return n
}

// Close stops the cleanup goroutine.
func (n *Notifier) Close() {
	close(n.done)
}

func (n *Notifier) cleanupLoop() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-n.done:
			return
		case <-ticker.C:
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			deleted, err := n.store.CleanupStalePushes(ctx, 30*time.Minute)
			cancel()
			if err != nil {
				log.Printf("push: stale push cleanup error: %v", err)
			} else if deleted > 0 {
				log.Printf("push: cleaned up %d stale push records", deleted)
			}
		}
	}
}

// NotifyAsync launches a goroutine to send push notifications to all registered
// devices. Push failures are logged but do not block the caller.
func (n *Notifier) NotifyAsync(sightingID int64, plateID int64, lat, lng float64) {
	go n.dispatch(sightingID, plateID, lat, lng)
}

func isDuplicate(pushes []db.SentPush, plateID int64, lat, lng float64) bool {
	for _, p := range pushes {
		if p.PlateID == plateID {
			return true
		}
		if geo.DistanceMiles(lat, lng, p.Latitude, p.Longitude) <= 1.0 {
			return true
		}
		if time.Since(p.SentAt) < 2*time.Minute {
			return true
		}
	}
	return false
}

func (n *Notifier) dispatch(sightingID int64, plateID int64, lat, lng float64) {
	if n.subs == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	activeSubscribers := n.subs.All()
	if len(activeSubscribers) == 0 {
		return
	}

	tokens, err := n.store.AllDeviceTokens(ctx)
	if err != nil {
		log.Printf("push: failed to query device tokens: %v", err)
		return
	}

	if len(tokens) == 0 {
		return
	}

	sightingIDStr := fmt.Sprintf("%d", sightingID)
	sent := 0

	for _, dt := range tokens {
		sub, ok := activeSubscribers[dt.HardwareID]
		if !ok {
			continue
		}
		if geo.DistanceMiles(lat, lng, sub.Lat, sub.Lng) > sub.RadiusMiles {
			continue
		}

		pushes, err := n.store.RecentPushesForDevice(ctx, dt.ID)
		if err != nil {
			log.Printf("push: failed to query recent pushes for device id=%d: %v", dt.ID, err)
			continue
		}
		if isDuplicate(pushes, plateID, lat, lng) {
			log.Printf("push: skipping duplicate notification for device id=%d", dt.ID)
			continue
		}

		var sendErr error

		switch dt.Platform {
		case "ios":
			if n.apns == nil {
				continue
			}
			sendErr = n.apns.SendNotification(
				dt.Token,
				"Potential ICE Activity Reported",
				"Potential ICE Activity reported",
				map[string]string{"sighting_id": sightingIDStr},
			)
			if sendErr == ErrAPNsTokenExpired {
				log.Printf("push: deleting expired APNs token id=%d", dt.ID)
				if delErr := n.store.DeleteDeviceToken(ctx, dt.ID); delErr != nil {
					log.Printf("push: failed to delete expired token id=%d: %v", dt.ID, delErr)
				}
				continue
			}

		case "android":
			if n.fcm == nil {
				continue
			}
			sendErr = n.fcm.Send(
				dt.Token,
				map[string]string{
					"sighting_id": sightingIDStr,
					"title":       "Potential ICE Activity Reported",
					"body":        "Potential ICE Activity reported",
				},
			)
			if sendErr == ErrFCMTokenExpired {
				log.Printf("push: deleting unregistered FCM token id=%d", dt.ID)
				if delErr := n.store.DeleteDeviceToken(ctx, dt.ID); delErr != nil {
					log.Printf("push: failed to delete expired token id=%d: %v", dt.ID, delErr)
				}
				continue
			}
		}

		if sendErr != nil {
			log.Printf("push: failed to send to device id=%d platform=%s: %v", dt.ID, dt.Platform, sendErr)
		} else {
			sent++
			if recErr := n.store.RecordSentPush(ctx, dt.ID, plateID, lat, lng); recErr != nil {
				log.Printf("push: failed to record sent push for device id=%d: %v", dt.ID, recErr)
			}
		}
	}
	if sent > 0 {
		log.Printf("push: sent %d notifications for sighting=%d", sent, sightingID)
	}
}
