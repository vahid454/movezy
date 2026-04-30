const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const User = require('../models/User');
const Driver = require('../models/Driver');
const Booking = require('../models/Booking');
const { authenticate, requireRole } = require('../middleware/auth');
const { sendPushNotification } = require('../utils/notifications');
const { BOOKING_STATUSES, enforceTransitionOrBypass } = require('../utils/bookingPolicy');
const { IDEMPOTENCY_ENABLED, getIdempotencyKey } = require('../utils/idempotency');
const { logAuditEvent } = require('../utils/auditLogger');

const toValidCoordinate = (value, min, max) => {
  const parsedValue = Number(value);
  if (!Number.isFinite(parsedValue) || parsedValue < min || parsedValue > max) {
    return null;
  }
  return parsedValue;
};

// Multer config
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/documents/'),
  filename: (req, file, cb) => cb(null, `${uuidv4()}${path.extname(file.originalname)}`)
});
const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = /jpeg|jpg|png|pdf/;
    cb(null, allowed.test(path.extname(file.originalname).toLowerCase()));
  }
});

const docFields = upload.fields([
  { name: 'licenseImage', maxCount: 1 },
  { name: 'vehicleRC', maxCount: 1 },
  { name: 'insurance', maxCount: 1 },
  { name: 'profilePhoto', maxCount: 1 }
]);

// POST /api/driver/register
router.post('/register', docFields, async (req, res) => {
  try {
    const { name, phone, drivingLicense, vehicleNumber, vehicleType, vehicleModel } = req.body;

    if (!name || !phone || !drivingLicense || !vehicleNumber || !vehicleType) {
      return res.status(400).json({ error: 'All fields are required.' });
    }

    const existingUser = await User.findOne({ phone });
    if (existingUser) return res.status(409).json({ error: 'Phone already registered.' });

    const existingDriver = await Driver.findOne({ vehicleNumber: vehicleNumber.toUpperCase() });
    if (existingDriver) return res.status(409).json({ error: 'Vehicle already registered.' });

    const user = await User.create({ name, phone, role: 'driver' });

    const documents = {};
    if (req.files) {
      if (req.files.licenseImage) documents.licenseImage = req.files.licenseImage[0].path;
      if (req.files.vehicleRC) documents.vehicleRC = req.files.vehicleRC[0].path;
      if (req.files.insurance) documents.insurance = req.files.insurance[0].path;
      if (req.files.profilePhoto) documents.profilePhoto = req.files.profilePhoto[0].path;
    }

    const driver = await Driver.create({
      user: user._id, name, phone, drivingLicense,
      vehicleNumber: vehicleNumber.toUpperCase(), vehicleType, vehicleModel, documents
    });

    res.status(201).json({
      success: true,
      message: 'Registration submitted. Awaiting admin approval.',
      driverId: driver._id
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/driver/profile
router.get('/profile', authenticate, requireRole('driver'), async (req, res) => {
  try {
    const driver = await Driver.findOne({ user: req.userId }).populate('user', 'name phone fcmToken');
    if (!driver) return res.status(404).json({ error: 'Driver not found' });
    res.json({ success: true, driver });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/driver/toggle-online
router.put('/toggle-online', authenticate, requireRole('driver'), async (req, res) => {
  try {
    const driver = await Driver.findOne({ user: req.userId });
    if (!driver) return res.status(404).json({ error: 'Driver not found' });
    if (driver.approvalStatus !== 'approved') return res.status(403).json({ error: 'Account not approved yet' });

    driver.isOnline = !driver.isOnline;
    await driver.save();

    if (req.io) {
      req.io.emit('driver_status_change', { driverId: driver._id, isOnline: driver.isOnline });
    }

    res.json({ success: true, isOnline: driver.isOnline });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/driver/update-location
router.put('/update-location', authenticate, requireRole('driver'), async (req, res) => {
  try {
    const { latitude, longitude } = req.body;
    const parsedLatitude = toValidCoordinate(latitude, -90, 90);
    const parsedLongitude = toValidCoordinate(longitude, -180, 180);
    if (parsedLatitude === null || parsedLongitude === null) {
      return res.status(400).json({ error: 'Valid latitude and longitude are required' });
    }

    const driver = await Driver.findOneAndUpdate(
      { user: req.userId },
      { location: { type: 'Point', coordinates: [parsedLongitude, parsedLatitude] } },
      { new: true }
    );

    await User.findByIdAndUpdate(req.userId, {
      location: { type: 'Point', coordinates: [parsedLongitude, parsedLatitude] },
      lastSeen: new Date()
    });

    if (req.io) {
      req.io.emit('driver_location_update', {
        driverId: driver._id,
        location: { latitude: parsedLatitude, longitude: parsedLongitude }
      });
    }

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/driver/respond-booking
router.post('/respond-booking', authenticate, requireRole('driver'), async (req, res) => {
  try {
    const { bookingId, action } = req.body; // action: 'accept' | 'reject'
    const idempotencyKey = IDEMPOTENCY_ENABLED ? getIdempotencyKey(req) : null;
    const driver = await Driver.findOne({ user: req.userId });
    if (!driver || driver.approvalStatus !== 'approved') return res.status(403).json({ error: 'Not authorized' });

    const booking = await Booking.findById(bookingId).populate('customer', 'name phone fcmToken');
    if (!booking) return res.status(404).json({ error: 'Booking not available' });
    if (
      IDEMPOTENCY_ENABLED
      && idempotencyKey
      && booking.acceptedByDriverRequestId === idempotencyKey
      && booking.driver
      && booking.driver.toString() === driver._id.toString()
      && booking.status === BOOKING_STATUSES.ACCEPTED
    ) {
      return res.status(200).json({ success: true, message: 'Booking already accepted', booking, idempotentReplay: true });
    }
    if (booking.status !== BOOKING_STATUSES.SEARCHING) return res.status(404).json({ error: 'Booking not available' });

    if (action === 'reject') {
      booking.rejectedByDrivers.push(driver._id);
      await booking.save();
      return res.json({ success: true, message: 'Booking rejected' });
    }

    // Accept
    booking.driver = driver._id;
    const transitionGuard = enforceTransitionOrBypass(booking.status, BOOKING_STATUSES.ACCEPTED);
    if (!transitionGuard.allowed) {
      return res.status(400).json({ error: transitionGuard.message });
    }

    booking.status = BOOKING_STATUSES.ACCEPTED;
    booking.acceptedAt = new Date();
    booking.acceptedByDriverRequestId = idempotencyKey || undefined;
    await booking.save();
    logAuditEvent({
      req,
      action: 'accept_booking',
      entityType: 'booking',
      entityId: booking._id,
      metadata: { driverId: driver._id }
    });

    driver.isAvailable = false;
    await driver.save();

    // Notify customer
    if (booking.customer.fcmToken) {
      await sendPushNotification(booking.customer.fcmToken, 'Driver Found! 🚗', `${driver.name} accepted your request`, { bookingId: booking._id.toString() });
    }

    if (req.io) {
      req.io.to(`booking_${booking._id}`).emit('booking_accepted', {
        bookingId: booking._id,
        driver: { id: driver._id, name: driver.name, phone: driver.phone, vehicleNumber: driver.vehicleNumber, vehicleType: driver.vehicleType, rating: driver.rating }
      });
    }

    res.json({ success: true, message: 'Booking accepted', booking });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/driver/start-trip
router.post('/start-trip', authenticate, requireRole('driver'), async (req, res) => {
  try {
    const { bookingId } = req.body;
    const driver = await Driver.findOne({ user: req.userId });
    const booking = await Booking.findById(bookingId).populate('customer', 'fcmToken');

    if (!booking || booking.driver.toString() !== driver._id.toString()) {
      return res.status(403).json({ error: 'Not authorized' });
    }

    const transitionGuard = enforceTransitionOrBypass(booking.status, BOOKING_STATUSES.IN_PROGRESS);
    if (!transitionGuard.allowed) {
      return res.status(400).json({ error: transitionGuard.message });
    }

    booking.status = BOOKING_STATUSES.IN_PROGRESS;
    booking.startedAt = new Date();
    await booking.save();
    logAuditEvent({
      req,
      action: 'start_trip',
      entityType: 'booking',
      entityId: booking._id,
      metadata: { driverId: driver._id }
    });

    if (booking.customer?.fcmToken) {
      await sendPushNotification(booking.customer.fcmToken, 'Trip Started! 🚀', 'Your goods are on the way', { bookingId: booking._id.toString() });
    }

    if (req.io) {
      req.io.to(`booking_${booking._id}`).emit('trip_started', { bookingId: booking._id });
    }

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/driver/complete-trip
router.post('/complete-trip', authenticate, requireRole('driver'), async (req, res) => {
  try {
    const { bookingId } = req.body;
    const driver = await Driver.findOne({ user: req.userId });
    const booking = await Booking.findById(bookingId).populate('customer', 'fcmToken');

    if (!booking || booking.driver.toString() !== driver._id.toString()) {
      return res.status(403).json({ error: 'Not authorized' });
    }

    const transitionGuard = enforceTransitionOrBypass(booking.status, BOOKING_STATUSES.COMPLETED);
    if (!transitionGuard.allowed) {
      return res.status(400).json({ error: transitionGuard.message });
    }

    booking.status = BOOKING_STATUSES.COMPLETED;
    booking.completedAt = new Date();
    await booking.save();
    logAuditEvent({
      req,
      action: 'complete_trip',
      entityType: 'booking',
      entityId: booking._id,
      metadata: { driverId: driver._id }
    });

    driver.isAvailable = true;
    driver.totalTrips += 1;
    await driver.save();

    if (booking.customer?.fcmToken) {
      await sendPushNotification(booking.customer.fcmToken, 'Trip Completed! ✅', 'Your delivery is done. Please rate your experience.', { bookingId: booking._id.toString() });
    }

    if (req.io) {
      req.io.to(`booking_${booking._id}`).emit('trip_completed', { bookingId: booking._id });
    }

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/driver/trip-history
router.get('/trip-history', authenticate, requireRole('driver'), async (req, res) => {
  try {
    const driver = await Driver.findOne({ user: req.userId });
    const bookings = await Booking.find({ driver: driver._id, status: { $in: ['completed', 'cancelled'] } })
      .populate('customer', 'name phone')
      .sort({ createdAt: -1 })
      .limit(50);
    res.json({ success: true, bookings });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
