package geo

import (
	"math"
	"testing"
)

func TestDistanceMiles_KnownDistances(t *testing.T) {
	tests := []struct {
		name                   string
		lat1, lng1, lat2, lng2 float64
		wantMiles              float64
		tolerance              float64
	}{
		{
			name: "New York to Los Angeles",
			lat1: 40.7128, lng1: -74.0060,
			lat2: 34.0522, lng2: -118.2437,
			wantMiles: 2451,
			tolerance: 10,
		},
		{
			name: "same point",
			lat1: 36.1627, lng1: -86.7816,
			lat2: 36.1627, lng2: -86.7816,
			wantMiles: 0,
			tolerance: 0.001,
		},
		{
			name: "Nashville to Memphis",
			lat1: 36.1627, lng1: -86.7816,
			lat2: 35.1495, lng2: -90.0490,
			wantMiles: 200,
			tolerance: 15,
		},
		{
			name: "short distance within a city",
			lat1: 36.16, lng1: -86.78,
			lat2: 36.17, lng2: -86.79,
			wantMiles: 0.9,
			tolerance: 0.2,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := DistanceMiles(tt.lat1, tt.lng1, tt.lat2, tt.lng2)
			if math.Abs(got-tt.wantMiles) > tt.tolerance {
				t.Errorf("DistanceMiles() = %.2f, want %.2f (+/- %.2f)", got, tt.wantMiles, tt.tolerance)
			}
		})
	}
}

func TestDistanceMiles_Symmetry(t *testing.T) {
	d1 := DistanceMiles(36.16, -86.78, 34.05, -118.24)
	d2 := DistanceMiles(34.05, -118.24, 36.16, -86.78)
	if math.Abs(d1-d2) > 0.001 {
		t.Errorf("distance is not symmetric: %f vs %f", d1, d2)
	}
}

func TestBoundingBoxFromCenter(t *testing.T) {
	bb := BoundingBoxFromCenter(36.16, -86.78, 10)

	if bb.MinLat >= 36.16 || bb.MaxLat <= 36.16 {
		t.Errorf("center latitude should be within bounds: min=%f max=%f", bb.MinLat, bb.MaxLat)
	}
	if bb.MinLng >= -86.78 || bb.MaxLng <= -86.78 {
		t.Errorf("center longitude should be within bounds: min=%f max=%f", bb.MinLng, bb.MaxLng)
	}

	latSpan := bb.MaxLat - bb.MinLat
	expectedLatSpan := 2 * 10.0 / 69.0
	if math.Abs(latSpan-expectedLatSpan) > 0.001 {
		t.Errorf("latitude span = %f, want %f", latSpan, expectedLatSpan)
	}
}

func TestBoundingBoxFromCenter_ContainsNearbyPoint(t *testing.T) {
	bb := BoundingBoxFromCenter(36.16, -86.78, 50)

	nearbyLat, nearbyLng := 36.30, -86.90
	if nearbyLat < bb.MinLat || nearbyLat > bb.MaxLat || nearbyLng < bb.MinLng || nearbyLng > bb.MaxLng {
		t.Errorf("nearby point (%.2f, %.2f) should be inside bounding box %+v", nearbyLat, nearbyLng, bb)
	}
}

func TestBoundingBoxFromCenter_ExcludesFarPoint(t *testing.T) {
	bb := BoundingBoxFromCenter(36.16, -86.78, 10)

	farLat, farLng := 34.05, -118.24
	inside := farLat >= bb.MinLat && farLat <= bb.MaxLat && farLng >= bb.MinLng && farLng <= bb.MaxLng
	if inside {
		t.Errorf("far point (%.2f, %.2f) should be outside bounding box %+v", farLat, farLng, bb)
	}
}
