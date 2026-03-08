package geo

import "math"

const earthRadiusMiles = 3958.8

// DistanceMiles returns the haversine distance in miles between two lat/lng points.
func DistanceMiles(lat1, lng1, lat2, lng2 float64) float64 {
	lat1r := lat1 * math.Pi / 180
	lat2r := lat2 * math.Pi / 180
	dLat := (lat2 - lat1) * math.Pi / 180
	dLng := (lng2 - lng1) * math.Pi / 180

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1r)*math.Cos(lat2r)*
			math.Sin(dLng/2)*math.Sin(dLng/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return earthRadiusMiles * c
}

// BoundingBox represents a rectangular region defined by lat/lng bounds.
type BoundingBox struct {
	MinLat, MaxLat float64
	MinLng, MaxLng float64
}

// BoundingBoxFromCenter returns a bounding box around a center point with
// the given radius in miles. This is an approximation used for fast SQL
// pre-filtering before precise haversine calculation.
func BoundingBoxFromCenter(lat, lng, radiusMiles float64) BoundingBox {
	// 1 degree of latitude is approximately 69.0 miles
	latDelta := radiusMiles / 69.0

	// 1 degree of longitude varies by latitude
	lngDelta := radiusMiles / (69.0 * math.Cos(lat*math.Pi/180))

	return BoundingBox{
		MinLat: lat - latDelta,
		MaxLat: lat + latDelta,
		MinLng: lng - lngDelta,
		MaxLng: lng + lngDelta,
	}
}
