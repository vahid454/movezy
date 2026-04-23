const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const User = require('../models/User');
const Driver = require('../models/Driver');
const Booking = require('../models/Booking');
const { authenticate, requireRole } = require('../middleware/auth');
const { sendPushNotification } = require('../utils/notifications');

// Haversine distance
const getDistance = (lat1, lon1, lat2, lon2) => {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLon/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
};

const estimateFare = (distanceKm, vehicleType) => {
  const rates = { bike: 8, auto: 12, mini_truck: 20, tempo: 30, truck: 50, pickup: 35 };
  const base = { bike: 20, auto: 30, mini_truck: 80, tempo: 100, truck: 200, pickup: 120 };
  return Math.round(base[vehicleType] + (rates[vehicleType] * distanceKm));
};

// POST /api/customer/create-booking
router.post('/create-booking', authenticate, requireRole('customer'), async (req, res) => {
  try {
    const { vehicleType, pickup, dropoff, description } = req.body;
    if (!vehicleType || !pickup || !dropoff) return res.status(400).json({ error: 'Missing required fields' });

    const distanceKm = getDistance(pickup.latitude, pickup.longitude, dropoff.latitude, dropoff.longitude);
    const estimatedFare = estimateFare(distanceKm, vehicleType);

    const booking = await Booking.create({
      bookingId: `MV${Date.now()}`,
      customer: req.userId,
      vehicleType,
      pickup: {
        address: pickup.address,
        location: { type: 'Point', coordinates: [pickup.longitude, pickup.latitude] }
      },
      dropoff: {
        address: dropoff.address,
        location: { type: 'Point', coordinates: [dropoff.longitude, dropoff.latitude] }
      },
      description,
      estimatedDistance: Math.round(distanceKm * 10) / 10,
      estimatedFare
    });

    // Find nearby drivers
    const nearbyDrivers = await Driver.find({
      approvalStatus: 'approved',
      isOnline: true,
      isAvailable: true,
      location: {
        $near: {
          $geometry: { type: 'Point', coordinates: [pickup.longitude, pickup.latitude] },
          $maxDistance: 5000
        }
      }
    }).populate('user', 'fcmToken name').limit(10);

    booking.notifiedDrivers = nearbyDrivers.map(d => d._id);
    await booking.save();

    // Notify drivers
    for (const driver of nearbyDrivers) {
      if (driver.user?.fcmToken) {
        await sendPushNotification(driver.user.fcmToken, 'New Request Nearby! 📦',
          `${vehicleType.toUpperCase()} needed: ${pickup.address} → ${dropoff.address}`,
          { bookingId: booking._id.toString(), type: 'new_booking' }
        );
      }
      if (req.io) {
        req.io.to(`driver_${driver._id}`).emit('new_booking_request', {
          bookingId: booking._id,
          bookingCode: booking.bookingId,
          vehicleType,
          pickup: { address: pickup.address, latitude: pickup.latitude, longitude: pickup.longitude },
          dropoff: { address: dropoff.address, latitude: dropoff.latitude, longitude: dropoff.longitude },
          description,
          estimatedDistance: booking.estimatedDistance,
          estimatedFare
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
        nearbyDriversCount: nearbyDrivers.length
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
    if (['completed', 'cancelled'].includes(booking.status)) {
      return res.status(400).json({ error: 'Cannot cancel this booking' });
    }

    booking.status = 'cancelled';
    booking.cancelledBy = 'customer';
    booking.cancellationReason = reason || 'Customer cancelled';
    await booking.save();

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
    res.json({ success: true, booking });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/customer/update-location
router.put('/update-location', authenticate, async (req, res) => {
  try {
    const { latitude, longitude } = req.body;
    await User.findByIdAndUpdate(req.userId, {
      location: { type: 'Point', coordinates: [parseFloat(longitude), parseFloat(latitude)] },
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
    const query = {
      approvalStatus: 'approved',
      isOnline: true,
      isAvailable: true,
      location: {
        $near: {
          $geometry: { type: 'Point', coordinates: [parseFloat(longitude), parseFloat(latitude)] },
          $maxDistance: 8000
        }
      }
    };
    if (vehicleType) query.vehicleType = vehicleType;
    const drivers = await Driver.find(query).select('name vehicleNumber vehicleType rating location').limit(20);
    res.json({ success: true, drivers });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
