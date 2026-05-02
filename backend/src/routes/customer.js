const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const User = require('../models/User');
const Driver = require('../models/Driver');
const Booking = require('../models/Booking');
const { authenticate, requireRole } = require('../middleware/auth');
const { sendMulticastNotification } = require('../utils/notifications');
const { BOOKING_STATUSES, enforceTransitionOrBypass } = require('../utils/bookingPolicy');
const { IDEMPOTENCY_ENABLED, getIdempotencyKey } = require('../utils/idempotency');
const { logAuditEvent } = require('../utils/auditLogger');
const { splitCustomerFare, attachFareSplit } = require('../utils/fareCommission');

const VEHICLE_FARE_CONFIG = {
  bike: { baseFare: 20, perKm: 8, minFare: 35 },
  auto: { baseFare: 30, perKm: 12, minFare: 55 },
  mini_truck: { baseFare: 80, perKm: 20, minFare: 140 },
  tempo: { baseFare: 100, perKm: 30, minFare: 180 },
  truck: { baseFare: 200, perKm: 50, minFare: 320 },
  pickup: { baseFare: 120, perKm: 35, minFare: 220 }
};

const VEHICLE_LABEL = {
  bike: 'Bike',
  auto: 'Auto',
  mini_truck: 'Mini truck',
  tempo: 'Tempo',
  truck: 'Truck',
  pickup: 'Pickup'
};

// Haversine distance
const getDistance = (lat1, lon1, lat2, lon2) => {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLon/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
};

const estimateFare = (distanceKm, vehicleType) => {
  const fareConfig = VEHICLE_FARE_CONFIG[vehicleType];
  if (!fareConfig) return null;

  const distance = Math.max(0, distanceKm);
  const baseDistanceFare = fareConfig.baseFare + (fareConfig.perKm * distance);
  const longDistanceSurcharge = distance > 10 ? (distance - 10) * (fareConfig.perKm * 0.2) : 0;
  const bookingFee = Number(process.env.BOOKING_PLATFORM_FEE || 10);
  const currentHour = new Date().getHours();
  const isPeakHour = (currentHour >= 8 && currentHour <= 11) || (currentHour >= 17 && currentHour <= 21);
  const peakMultiplier = isPeakHour ? Number(process.env.PEAK_HOUR_MULTIPLIER || 1.2) : 1;

  const grossFare = (baseDistanceFare + longDistanceSurcharge + bookingFee) * peakMultiplier;
  return Math.round(Math.max(fareConfig.minFare, grossFare));
};

const toValidCoordinate = (value, min, max) => {
  const parsedValue = Number(value);
  if (!Number.isFinite(parsedValue) || parsedValue < min || parsedValue > max) {
    return null;
  }
  return parsedValue;
};

/** GeoJSON Point on drivers is [lng, lat]. Returns null if unusable. */
const driverLngLat = (driver) => {
  const coords = driver?.location?.coordinates;
  if (!Array.isArray(coords) || coords.length < 2) return null;
  const lng = Number(coords[0]);
  const lat = Number(coords[1]);
  if (!Number.isFinite(lng) || !Number.isFinite(lat)) return null;
  return { lat, lng };
};

/**
 * Nearby matching without Mongo $near — avoids "unknown GeoJSON type" when any
 * driver document has a malformed `location` field that still slips past filters.
 */
const sortDriversByDistanceKm = (drivers, centerLat, centerLng, maxRadiusKm) => {
  const scored = [];
  for (const d of drivers) {
    const ll = driverLngLat(d);
    if (!ll) continue;
    const km = getDistance(centerLat, centerLng, ll.lat, ll.lng);
    if (km <= maxRadiusKm) scored.push({ doc: d, km });
  }
  scored.sort((a, b) => a.km - b.km);
  return scored.map((s) => s.doc);
};

const normalizeLocation = (location) => {
  if (!location || typeof location !== 'object') return null;

  const latitude = toValidCoordinate(location.latitude, -90, 90);
  const longitude = toValidCoordinate(location.longitude, -180, 180);
  const address = typeof location.address === 'string' ? location.address.trim() : '';
  if (latitude === null || longitude === null || !address) return null;

  return { latitude, longitude, address };
};

// GET /api/customer/fare-quote
router.get('/fare-quote', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const originLat = toValidCoordinate(req.query.originLat, -90, 90);
    const originLng = toValidCoordinate(req.query.originLng, -180, 180);
    const destinationLat = toValidCoordinate(req.query.destinationLat, -90, 90);
    const destinationLng = toValidCoordinate(req.query.destinationLng, -180, 180);
    const vehicleType = `${req.query.vehicleType || ''}`.trim();
    if (!originLat || !originLng || !destinationLat || !destinationLng || !vehicleType) {
      return res.status(400).json({ error: 'Invalid fare quote request' });
    }
    if (!Object.prototype.hasOwnProperty.call(VEHICLE_FARE_CONFIG, vehicleType)) {
      return res.status(400).json({ error: 'Unsupported vehicle type' });
    }
    const distanceKm = getDistance(originLat, originLng, destinationLat, destinationLng);
    const estimatedFare = estimateFare(distanceKm, vehicleType);
    const { platformFee, driverPayout } = splitCustomerFare(estimatedFare);
    return res.json({
      success: true,
      estimatedFare,
      estimatedDistance: Math.round(distanceKm * 10) / 10,
      platformFee,
      driverPayout
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// POST /api/customer/create-booking
router.post('/create-booking', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const { vehicleType, pickup, dropoff, description } = req.body;
    const idempotencyKey = IDEMPOTENCY_ENABLED ? getIdempotencyKey(req) : null;
    if (!vehicleType || !pickup || !dropoff) return res.status(400).json({ error: 'Missing required fields' });
    if (!Object.prototype.hasOwnProperty.call(VEHICLE_FARE_CONFIG, vehicleType)) {
      return res.status(400).json({ error: 'Unsupported vehicle type' });
    }

    const normalizedPickup = normalizeLocation(pickup);
    const normalizedDropoff = normalizeLocation(dropoff);
    if (!normalizedPickup || !normalizedDropoff) {
      return res.status(400).json({ error: 'Invalid pickup or dropoff coordinates' });
    }

    const distanceKm = getDistance(
      normalizedPickup.latitude,
      normalizedPickup.longitude,
      normalizedDropoff.latitude,
      normalizedDropoff.longitude
    );
    const estimatedFare = estimateFare(distanceKm, vehicleType);
    if (estimatedFare === null) return res.status(400).json({ error: 'Unable to estimate fare' });
    const { platformFee, driverPayout } = splitCustomerFare(estimatedFare);

    if (IDEMPOTENCY_ENABLED && idempotencyKey) {
      const existingBooking = await Booking.findOne({
        customer: req.userId,
        createBookingIdempotencyKey: idempotencyKey
      });
      if (existingBooking) {
        const sp = splitCustomerFare(existingBooking.estimatedFare);
        return res.status(200).json({
          success: true,
          booking: {
            id: existingBooking._id,
            bookingId: existingBooking.bookingId,
            status: existingBooking.status,
            estimatedFare: existingBooking.estimatedFare,
            estimatedDistance: existingBooking.estimatedDistance,
            nearbyDriversCount: existingBooking.notifiedDrivers?.length || 0,
            platformFee: existingBooking.platformFee ?? sp.platformFee,
            driverPayout: existingBooking.driverPayout ?? sp.driverPayout
          },
          idempotentReplay: true
        });
      }
    }

    let booking;
    try {
      booking = await Booking.create({
        bookingId: `MV${Date.now()}`,
        customer: req.userId,
        vehicleType,
        pickup: {
          address: normalizedPickup.address,
          location: { type: 'Point', coordinates: [normalizedPickup.longitude, normalizedPickup.latitude] }
        },
        dropoff: {
          address: normalizedDropoff.address,
          location: { type: 'Point', coordinates: [normalizedDropoff.longitude, normalizedDropoff.latitude] }
        },
        description,
        estimatedDistance: Math.round(distanceKm * 10) / 10,
        estimatedFare,
        platformFee,
        driverPayout,
        createBookingIdempotencyKey: idempotencyKey || undefined
      });
    } catch (createError) {
      if (IDEMPOTENCY_ENABLED && idempotencyKey && createError?.code === 11000) {
        const replayBooking = await Booking.findOne({
          customer: req.userId,
          createBookingIdempotencyKey: idempotencyKey
        });
        if (replayBooking) {
          const sp = splitCustomerFare(replayBooking.estimatedFare);
          return res.status(200).json({
            success: true,
            booking: {
              id: replayBooking._id,
              bookingId: replayBooking.bookingId,
              status: replayBooking.status,
              estimatedFare: replayBooking.estimatedFare,
              estimatedDistance: replayBooking.estimatedDistance,
              nearbyDriversCount: replayBooking.notifiedDrivers?.length || 0,
              platformFee: replayBooking.platformFee ?? sp.platformFee,
              driverPayout: replayBooking.driverPayout ?? sp.driverPayout
            },
            idempotentReplay: true
          });
        }
      }
      throw createError;
    }
    logAuditEvent({
      req,
      action: 'create_booking',
      entityType: 'booking',
      entityId: booking._id,
      metadata: { vehicleType, estimatedFare }
    });

    const driverCandidates = await Driver.find({
      approvalStatus: 'approved',
      isOnline: true,
      isAvailable: true
    }).populate('user', 'fcmToken name').limit(120);

    const nearbyDrivers = sortDriversByDistanceKm(
      driverCandidates,
      normalizedPickup.latitude,
      normalizedPickup.longitude,
      12
    ).slice(0, 40);

    booking.notifiedDrivers = nearbyDrivers.map(d => d._id);
    await booking.save();

    const vLabel = VEHICLE_LABEL[vehicleType] || vehicleType;
    const pushTitle = `Movezy · New ${vLabel} job`;
    const pushBody = `₹${estimatedFare} est. · ${normalizedPickup.address} → ${normalizedDropoff.address}`;
    const pushData = {
      bookingId: booking._id.toString(),
      type: 'new_booking',
      vehicleType: `${vehicleType}`
    };
    const fcmTokens = [...new Set(
      nearbyDrivers.map((d) => d.user?.fcmToken).filter(Boolean)
    )];
    if (fcmTokens.length) {
      await sendMulticastNotification(fcmTokens, pushTitle, pushBody, pushData);
    }

    for (const driver of nearbyDrivers) {
      if (req.io) {
        req.io.to(`driver_${driver._id}`).emit('new_booking_request', {
          bookingId: booking._id,
          bookingCode: booking.bookingId,
          vehicleType,
          pickup: normalizedPickup,
          dropoff: normalizedDropoff,
          description,
          estimatedDistance: booking.estimatedDistance,
          estimatedFare,
          platformFee,
          driverPayout
        });
      }
    }

    res.status(201).json({
      success: true,
      booking: {
        id: booking._id,
        bookingId: booking.bookingId,
        status: booking.status,
        estimatedFare,
        estimatedDistance: booking.estimatedDistance,
        nearbyDriversCount: nearbyDrivers.length,
        platformFee,
        driverPayout
      }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/customer/booking/:id
router.get('/booking/:id', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const booking = await Booking.findById(req.params.id)
      .populate('customer', 'name phone')
      .populate({
        path: 'driver',
        populate: { path: 'user', select: 'name phone' }
      });
    if (!booking || booking.customer._id.toString() !== req.userId.toString()) {
      return res.status(404).json({ error: 'Booking not found' });
    }
    res.json({ success: true, booking });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/customer/cancel-booking
router.post('/cancel-booking', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const { bookingId, reason } = req.body;
    const booking = await Booking.findById(bookingId).populate('driver');
    if (!booking || booking.customer.toString() !== req.userId.toString()) {
      return res.status(404).json({ error: 'Booking not found' });
    }
    if ([BOOKING_STATUSES.COMPLETED, BOOKING_STATUSES.CANCELLED, BOOKING_STATUSES.IN_PROGRESS].includes(booking.status)) {
      return res.status(400).json({ error: 'Cannot cancel this booking' });
    }

    const transitionGuard = enforceTransitionOrBypass(booking.status, BOOKING_STATUSES.CANCELLED);
    if (!transitionGuard.allowed) {
      return res.status(400).json({ error: transitionGuard.message });
    }

    booking.status = BOOKING_STATUSES.CANCELLED;
    booking.cancelledBy = 'customer';
    booking.cancellationReason = reason || 'Customer cancelled';
    await booking.save();
    logAuditEvent({
      req,
      action: 'cancel_booking',
      entityType: 'booking',
      entityId: booking._id,
      metadata: { cancelledBy: 'customer', reason: booking.cancellationReason }
    });

    if (booking.driver) {
      const driver = await Driver.findById(booking.driver);
      if (driver) { driver.isAvailable = true; await driver.save(); }
    }

    if (req.io) {
      req.io.to(`booking_${booking._id}`).emit('booking_cancelled', { bookingId: booking._id, by: 'customer' });
    }

    res.json({ success: true, message: 'Booking cancelled' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/customer/places-autocomplete
router.get('/places-autocomplete', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const query = `${req.query.query || ''}`.trim();
    if (query.length < 3) {
      return res.json({ success: true, predictions: [] });
    }
    const apiKey = process.env.GOOGLE_MAPS_SERVER_API_KEY;
    if (!apiKey) {
      return res.json({ success: true, predictions: [] });
    }
    const endpoint = `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(query)}&components=country:in&key=${apiKey}`;
    const response = await fetch(endpoint);
    if (!response.ok) {
      return res.json({ success: true, predictions: [] });
    }
    const data = await response.json();
    const predictions = Array.isArray(data.predictions) ? data.predictions : [];
    return res.json({
      success: true,
      predictions: predictions.slice(0, 5).map((item) => ({
        placeId: item.place_id,
        primaryText: item.structured_formatting?.main_text || item.description || '',
        secondaryText: item.structured_formatting?.secondary_text || '',
        description: item.description || ''
      }))
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// POST /api/customer/rate-booking
router.post('/rate-booking', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const { bookingId, rating, review } = req.body;
    const booking = await Booking.findById(bookingId);
    if (!booking || booking.customer.toString() !== req.userId.toString()) return res.status(404).json({ error: 'Not found' });
    if (booking.status !== 'completed') return res.status(400).json({ error: 'Can only rate completed trips' });

    booking.customerRating = rating;
    booking.customerReview = review;
    await booking.save();

    // Update driver rating average
    if (booking.driver) {
      const allRatedBookings = await Booking.find({ driver: booking.driver, customerRating: { $exists: true } });
      const avgRating = allRatedBookings.reduce((s, b) => s + b.customerRating, 0) / allRatedBookings.length;
      await Driver.findByIdAndUpdate(booking.driver, { rating: Math.round(avgRating * 10) / 10 });
    }

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/customer/booking-history
router.get('/booking-history', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const bookings = await Booking.find({ customer: req.userId })
      .populate({ path: 'driver', populate: { path: 'user', select: 'name phone' } })
      .sort({ createdAt: -1 })
      .limit(50);
    res.json({ success: true, bookings });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/customer/active-booking
router.get('/active-booking', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const booking = await Booking.findOne({
      customer: req.userId,
      status: { $in: ['searching', 'accepted', 'driver_arriving', 'in_progress'] }
    }).populate({ path: 'driver', populate: { path: 'user', select: 'name phone' } });
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

// PUT /api/customer/update-location
router.put('/update-location', authenticate, async (req, res) => {
  try {
    const { latitude, longitude } = req.body;
    const parsedLatitude = toValidCoordinate(latitude, -90, 90);
    const parsedLongitude = toValidCoordinate(longitude, -180, 180);
    if (parsedLatitude === null || parsedLongitude === null) {
      return res.status(400).json({ error: 'Valid latitude and longitude are required' });
    }

    await User.findByIdAndUpdate(req.userId, {
      location: { type: 'Point', coordinates: [parsedLongitude, parsedLatitude] },
      lastSeen: new Date()
    });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/customer/nearby-drivers
router.get('/nearby-drivers', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const { latitude, longitude, vehicleType } = req.query;
    const parsedLatitude = toValidCoordinate(latitude, -90, 90);
    const parsedLongitude = toValidCoordinate(longitude, -180, 180);
    if (parsedLatitude === null || parsedLongitude === null) {
      return res.status(400).json({ error: 'Valid latitude and longitude are required' });
    }
    if (vehicleType && !Object.prototype.hasOwnProperty.call(VEHICLE_FARE_CONFIG, vehicleType)) {
      return res.status(400).json({ error: 'Unsupported vehicle type' });
    }

    const query = {
      approvalStatus: 'approved',
      isOnline: true,
      isAvailable: true
    };
    if (vehicleType) query.vehicleType = vehicleType;
    const driverCandidates = await Driver.find(query)
      .select('name phone vehicleNumber vehicleType rating location')
      .limit(120);
    const drivers = sortDriversByDistanceKm(
      driverCandidates,
      parsedLatitude,
      parsedLongitude,
      8
    ).slice(0, 20);
    res.json({ success: true, drivers });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
