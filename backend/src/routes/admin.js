const express = require('express');
const router = express.Router();
const User = require('../models/User');
const Driver = require('../models/Driver');
const Booking = require('../models/Booking');
const { authenticate, requireRole } = require('../middleware/auth');
const { sendPushNotification } = require('../utils/notifications');
const { logAuditEvent } = require('../utils/auditLogger');

const toAbsoluteAssetUrl = (req, documentPath) => {
  if (!documentPath) return documentPath;
  if (/^https?:\/\//i.test(documentPath)) return documentPath;

  let normalizedPath = documentPath;
  if (!normalizedPath.startsWith('/')) {
    if (normalizedPath.includes('/uploads/')) {
      normalizedPath = normalizedPath.slice(normalizedPath.indexOf('/uploads/'));
    } else if (normalizedPath.startsWith('uploads/')) {
      normalizedPath = `/${normalizedPath}`;
    } else {
      return documentPath;
    }
  }

  return `${req.protocol}://${req.get('host')}${normalizedPath}`;
};

const normalizeDriverDocuments = (req, driver) => {
  if (!driver) return driver;
  const driverObj = typeof driver.toObject === 'function' ? driver.toObject() : driver;
  if (!driverObj.documents) return driverObj;

  return {
    ...driverObj,
    documents: {
      ...driverObj.documents,
      licenseImage: toAbsoluteAssetUrl(req, driverObj.documents.licenseImage),
      vehicleRC: toAbsoluteAssetUrl(req, driverObj.documents.vehicleRC),
      insurance: toAbsoluteAssetUrl(req, driverObj.documents.insurance),
      profilePhoto: toAbsoluteAssetUrl(req, driverObj.documents.profilePhoto)
    }
  };
};

// GET /api/admin/dashboard
router.get('/dashboard', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    const [
      totalUsers,
      totalDrivers,
      pendingDrivers,
      approvedDrivers,
      onlineDrivers,
      availableDrivers,
      totalBookings,
      activeBookings,
      searchingBookings,
      completedBookings,
      completedToday,
      cancelledToday
    ] = await Promise.all([
      User.countDocuments({ role: 'customer' }),
      Driver.countDocuments(),
      Driver.countDocuments({ approvalStatus: 'pending' }),
      Driver.countDocuments({ approvalStatus: 'approved' }),
      Driver.countDocuments({ approvalStatus: 'approved', isOnline: true }),
      Driver.countDocuments({ approvalStatus: 'approved', isAvailable: true }),
      Booking.countDocuments(),
      Booking.countDocuments({ status: { $in: ['searching', 'accepted', 'in_progress'] } }),
      Booking.countDocuments({ status: 'searching' }),
      Booking.countDocuments({ status: 'completed' }),
      Booking.countDocuments({ status: 'completed', completedAt: { $gte: todayStart } }),
      Booking.countDocuments({ status: 'cancelled', updatedAt: { $gte: todayStart } })
    ]);

    // Bookings by day (last 7 days)
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const bookingsByDay = await Booking.aggregate([
      { $match: { createdAt: { $gte: sevenDaysAgo } } },
      { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } }, count: { $sum: 1 } } },
      { $sort: { _id: 1 } }
    ]);

    // Vehicle type distribution
    const vehicleDistribution = await Booking.aggregate([
      { $group: { _id: '$vehicleType', count: { $sum: 1 } } }
    ]);

    const [liveBookings, liveDrivers] = await Promise.all([
      Booking.find({ status: { $in: ['searching', 'accepted', 'in_progress'] } })
        .populate('customer', 'name phone')
        .populate({ path: 'driver', populate: { path: 'user', select: 'name phone' } })
        .sort({ updatedAt: -1 })
        .limit(8),
      Driver.find({ approvalStatus: 'approved', isOnline: true })
        .populate('user', 'lastSeen')
        .sort({ updatedAt: -1 })
        .limit(8)
    ]);

    res.json({
      success: true,
      stats: {
        totalUsers,
        totalDrivers,
        pendingDrivers,
        approvedDrivers,
        onlineDrivers,
        availableDrivers,
        totalBookings,
        activeBookings,
        searchingBookings,
        completedBookings,
        completedToday,
        cancelledToday
      },
      charts: { bookingsByDay, vehicleDistribution },
      live: {
        bookings: liveBookings.map((booking) => ({
          id: booking._id,
          bookingId: booking.bookingId,
          status: booking.status,
          vehicleType: booking.vehicleType,
          estimatedFare: booking.estimatedFare,
          estimatedDistance: booking.estimatedDistance,
          pickup: booking.pickup?.address,
          dropoff: booking.dropoff?.address,
          customer: booking.customer
            ? {
                name: booking.customer.name,
                phone: booking.customer.phone
              }
            : null,
          driver: booking.driver
            ? {
                name: booking.driver.name,
                phone: booking.driver.phone,
                vehicleNumber: booking.driver.vehicleNumber
              }
            : null,
          updatedAt: booking.updatedAt
        })),
        drivers: liveDrivers.map((driver) => ({
          id: driver._id,
          name: driver.name,
          phone: driver.phone,
          vehicleNumber: driver.vehicleNumber,
          vehicleType: driver.vehicleType,
          isAvailable: driver.isAvailable,
          rating: driver.rating,
          lastSeen: driver.user?.lastSeen,
          latitude: driver.location?.coordinates?.[1] ?? null,
          longitude: driver.location?.coordinates?.[0] ?? null
        }))
      }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/drivers
router.get('/drivers', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const { status, page = 1, limit = 20 } = req.query;
    const query = {};
    if (status) query.approvalStatus = status;
    const drivers = await Driver.find(query)
      .populate('user', 'name phone createdAt')
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(parseInt(limit));
    const total = await Driver.countDocuments(query);
    res.json({
      success: true,
      drivers: drivers.map((driver) => normalizeDriverDocuments(req, driver)),
      total,
      pages: Math.ceil(total / limit)
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/driver/:id
router.get('/driver/:id', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const driver = await Driver.findById(req.params.id).populate('user', 'name phone createdAt lastSeen');
    if (!driver) return res.status(404).json({ error: 'Driver not found' });
    res.json({ success: true, driver: normalizeDriverDocuments(req, driver) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/admin/driver/:id/approve
router.put('/driver/:id/approve', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const driver = await Driver.findById(req.params.id).populate('user', 'fcmToken');
    if (!driver) return res.status(404).json({ error: 'Driver not found' });

    driver.approvalStatus = 'approved';
    driver.reviewedBy = req.userId;
    driver.reviewedAt = new Date();
    await driver.save();
    logAuditEvent({
      req,
      action: 'approve_driver',
      entityType: 'driver',
      entityId: driver._id,
      metadata: { approvalStatus: driver.approvalStatus }
    });

    if (driver.user?.fcmToken) {
      await sendPushNotification(driver.user.fcmToken, '🎉 Account Approved!',
        'Your Movezy driver account has been approved. You can now go online and accept trips!',
        { type: 'approval', status: 'approved' }
      );
    }

    res.json({ success: true, message: 'Driver approved' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/admin/driver/:id/reject
router.put('/driver/:id/reject', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const { reason } = req.body;
    const driver = await Driver.findById(req.params.id).populate('user', 'fcmToken');
    if (!driver) return res.status(404).json({ error: 'Driver not found' });

    driver.approvalStatus = 'rejected';
    driver.rejectionReason = reason || 'Documents not valid';
    driver.reviewedBy = req.userId;
    driver.reviewedAt = new Date();
    await driver.save();
    logAuditEvent({
      req,
      action: 'reject_driver',
      entityType: 'driver',
      entityId: driver._id,
      metadata: { rejectionReason: driver.rejectionReason }
    });

    if (driver.user?.fcmToken) {
      await sendPushNotification(driver.user.fcmToken, 'Account Review Update',
        `Your application was not approved. Reason: ${driver.rejectionReason}`,
        { type: 'approval', status: 'rejected' }
      );
    }

    res.json({ success: true, message: 'Driver rejected' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/users
router.get('/users', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const users = await User.find({ role: 'customer' })
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(parseInt(limit));
    const total = await User.countDocuments({ role: 'customer' });
    res.json({ success: true, users, total });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/bookings
router.get('/bookings', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const { status, page = 1, limit = 20 } = req.query;
    const query = {};
    if (status) query.status = status;
    const bookings = await Booking.find(query)
      .populate('customer', 'name phone')
      .populate({ path: 'driver', populate: { path: 'user', select: 'name phone' } })
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(parseInt(limit));
    const total = await Booking.countDocuments(query);
    res.json({ success: true, bookings, total });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/admin/user/:id/toggle
router.put('/user/:id/toggle', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const user = await User.findById(req.params.id);
    if (!user) return res.status(404).json({ error: 'User not found' });
    user.isActive = !user.isActive;
    await user.save();
    logAuditEvent({
      req,
      action: user.isActive ? 'activate_user' : 'deactivate_user',
      entityType: 'user',
      entityId: user._id
    });
    res.json({ success: true, isActive: user.isActive });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
