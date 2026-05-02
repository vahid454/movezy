const express = require('express');
const router = express.Router();
const Booking = require('../models/Booking');
const Driver = require('../models/Driver');
const { authenticate } = require('../middleware/auth');
const { attachFareSplit } = require('../utils/fareCommission');
const { canAccessBooking, STRICT_POLICY_ENABLED } = require('../utils/bookingPolicy');

const toCoordinate = (value, min, max) => {
  const parsedValue = Number(value);
  if (!Number.isFinite(parsedValue) || parsedValue < min || parsedValue > max) {
    return null;
  }
  return parsedValue;
};

const toLngLatPoints = (latLngPoints) => latLngPoints.map((point) => [point[1], point[0]]);

const getFallbackPath = (originLat, originLng, destinationLat, destinationLng) => ([
  [originLng, originLat],
  [destinationLng, destinationLat]
]);

const decodeGooglePolyline = (encodedPath) => {
  let index = 0;
  let latitude = 0;
  let longitude = 0;
  const points = [];

  while (index < encodedPath.length) {
    let shift = 0;
    let result = 0;
    let byte;

    do {
      byte = encodedPath.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const latitudeDelta = (result & 1) !== 0 ? ~(result >> 1) : (result >> 1);
    latitude += latitudeDelta;

    shift = 0;
    result = 0;
    do {
      byte = encodedPath.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const longitudeDelta = (result & 1) !== 0 ? ~(result >> 1) : (result >> 1);
    longitude += longitudeDelta;

    points.push([latitude / 1e5, longitude / 1e5]);
  }

  return points;
};

const fetchGoogleDirectionsPath = async (originLat, originLng, destinationLat, destinationLng) => {
  const googleApiKey = process.env.GOOGLE_MAPS_SERVER_API_KEY;
  if (!googleApiKey) return null;

  const googleDirectionsUrl = `https://maps.googleapis.com/maps/api/directions/json?origin=${originLat},${originLng}&destination=${destinationLat},${destinationLng}&mode=driving&key=${googleApiKey}`;
  const response = await fetch(googleDirectionsUrl);
  if (!response.ok) return null;

  const responseJson = await response.json();
  const encodedPolyline = responseJson?.routes?.[0]?.overview_polyline?.points;
  if (!encodedPolyline || typeof encodedPolyline !== 'string') return null;

  const decodedPoints = decodeGooglePolyline(encodedPolyline);
  if (decodedPoints.length < 2) return null;

  return {
    source: 'google_directions',
    coordinates: toLngLatPoints(decodedPoints)
  };
};

const fetchOsrmPath = async (originLat, originLng, destinationLat, destinationLng) => {
  const osrmBaseUrl = process.env.OSRM_BASE_URL || 'https://router.project-osrm.org';
  const osrmUrl = `${osrmBaseUrl}/route/v1/driving/${originLng},${originLat};${destinationLng},${destinationLat}?overview=full&geometries=geojson`;
  const routeResponse = await fetch(osrmUrl);
  if (!routeResponse.ok) return null;

  const routeJson = await routeResponse.json();
  const routeCoordinates = routeJson?.routes?.[0]?.geometry?.coordinates;
  if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2) return null;

  return {
    source: 'osrm',
    coordinates: routeCoordinates
  };
};

// GET /api/booking/route-path
router.get('/route-path', authenticate, async (req, res) => {
  try {
    const originLat = toCoordinate(req.query.originLat, -90, 90);
    const originLng = toCoordinate(req.query.originLng, -180, 180);
    const destinationLat = toCoordinate(req.query.destinationLat, -90, 90);
    const destinationLng = toCoordinate(req.query.destinationLng, -180, 180);

    if (
      originLat === null
      || originLng === null
      || destinationLat === null
      || destinationLng === null
    ) {
      return res.status(400).json({ error: 'Invalid route coordinates' });
    }

    const googleRoute = await fetchGoogleDirectionsPath(
      originLat,
      originLng,
      destinationLat,
      destinationLng
    );
    if (googleRoute) {
      return res.json({
        success: true,
        source: googleRoute.source,
        coordinates: googleRoute.coordinates
      });
    }

    const osrmRoute = await fetchOsrmPath(
      originLat,
      originLng,
      destinationLat,
      destinationLng
    );
    if (osrmRoute) {
      return res.json({
        success: true,
        source: osrmRoute.source,
        coordinates: osrmRoute.coordinates
      });
    }

    return res.json({
      success: true,
      source: 'fallback',
      coordinates: getFallbackPath(originLat, originLng, destinationLat, destinationLng)
    });
  } catch (err) {
    return res.json({
      success: true,
      source: 'fallback',
      coordinates: []
    });
  }
});

// GET /api/booking/:id/status - Poll booking status
router.get('/:id/status', authenticate, async (req, res) => {
  try {
    const booking = await Booking.findById(req.params.id)
      .populate('customer', 'name phone')
      .populate({ path: 'driver', populate: { path: 'user', select: 'name phone' } });

    if (!booking) return res.status(404).json({ error: 'Booking not found' });
    if (STRICT_POLICY_ENABLED) {
      let driverRecord = null;
      if (req.user.role === 'driver') {
        driverRecord = await Driver.findOne({ user: req.userId }).select('_id');
      }

      const hasAccess = canAccessBooking({
        booking,
        userId: req.userId,
        role: req.user.role,
        driverId: driverRecord?._id
      });

      if (!hasAccess) return res.status(403).json({ error: 'Forbidden: cannot access this booking' });
    }

    res.json({
      success: true,
      booking: attachFareSplit(booking.toObject({ flattenMaps: true }))
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/booking/driver/active - Driver's active booking
router.get('/driver/active', authenticate, async (req, res) => {
  try {
    const driver = await Driver.findOne({ user: req.userId });
    if (!driver) return res.status(404).json({ error: 'Driver not found' });

    const booking = await Booking.findOne({
      driver: driver._id,
      status: { $in: ['accepted', 'driver_arriving', 'in_progress'] }
    }).populate('customer', 'name phone location');

    if (!booking) {
      return res.json({ success: true, booking: null });
    }
    res.json({
      success: true,
      booking: attachFareSplit(booking.toObject({ flattenMaps: true }))
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
