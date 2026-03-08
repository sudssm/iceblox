package push

import (
	"context"
	"fmt"
	"log"
	"time"

	"cameras/server/internal/db"
	"cameras/server/internal/geo"
	"cameras/server/internal/subscribers"
)

// TokenStore provides access to device tokens for push notifications.
type TokenStore interface {
	AllDeviceTokens(ctx context.Context) ([]db.DeviceToken, error)
	DeleteDeviceToken(ctx context.Context, id int64) error
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
}

// NewNotifier creates a Notifier. Both apns and fcm may be nil if not configured.
func NewNotifier(apns *APNsClient, fcm *FCMClient, store TokenStore, subs SubscriberStore) *Notifier {
	return &Notifier{
		apns:  apns,
		fcm:   fcm,
		store: store,
		subs:  subs,
	}
}

// NotifyAsync launches a goroutine to send push notifications to all registered
// devices. Push failures are logged but do not block the caller.
func (n *Notifier) NotifyAsync(sightingID int64, lat, lng float64) {
	go n.dispatch(sightingID, lat, lng)
}

func (n *Notifier) dispatch(sightingID int64, lat, lng float64) {
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

	for _, dt := range tokens {
		sub, ok := activeSubscribers[dt.HardwareID]
		if !ok {
			continue
		}
		if geo.DistanceMiles(lat, lng, sub.Lat, sub.Lng) > sub.RadiusMiles {
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
				"Target Detected",
				"A target plate was detected",
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
					"title":       "Target Detected",
					"body":        "A target plate was detected",
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
		}
	}
}
