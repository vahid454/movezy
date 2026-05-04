const express = require('express');
const mongoose = require('mongoose');
const router = express.Router();
const User = require('../models/User');
const Driver = require('../models/Driver');
const Booking = require('../models/Booking');
const { authenticate, requireRole } = require('../middleware/auth');
const { sendPushNotification } = require('../utils/notifications');
const { logAuditEvent } = require('../utils/auditLogger');
const { attachFareSplit, commissionPercent } = require('../utils/fareCommission');

const escapeRegex = (s) => `${s}`.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const buildTextRegex = (q) => new RegExp(escapeRegex(q.trim()), 'i');

const bookingSearchConditions = async (q) => {
  const trimmed = `${q || ''}`.trim();
  if (trimmed.length < 2) return null;
  const rx = buildTextRegex(trimmed);
  const parts = [
    { bookingId: rx },
    { 'pickup.address': rx },
    { 'dropoff.address': rx }
  ];
  const [custIds, drvIds] = await Promise.all([
    User.find({ role: 'customer', $or: [{ phone: rx }, { name: rx }] }).distinct('_id').lean(),
    Driver.find({
      $or: [{ phone: rx }, { name: rx }, { vehicleNumber: rx }, { drivingLicense: rx }]
    }).distinct('_id').lean()
  ]);
  if (custIds.length) parts.push({ customer: { $in: custIds } });
  if (drvIds.length) parts.push({ driver: { $in: drvIds } });
  if (mongoose.Types.ObjectId.isValid(trimmed) && `${trimmed}`.length === 24) {
    try {
      parts.push({ _id: new mongoose.Types.ObjectId(trimmed) });
    } catch (_) {
      /* ignore invalid hex */
    }
  }
  return { $or: parts };
};

const serializeAdminBooking = (booking) => {
  if (!booking) return booking;
  const plain = typeof booking.toObject === 'function' ? booking.toObject() : { ...booking };
  return attachFareSplit(plain);
};

const mergeStatusAndSearch = (baseFilter, searchFilter) => {
  if (!searchFilter) return baseFilter;
  const keys = Object.keys(baseFilter || {});
  if (!keys.length) return searchFilter;
  return { $and: [baseFilter, searchFilter] };
};

const toAbsoluteAssetUrl = (req, documentPath) => {
  if (!documentPath) return documentPath;
  if (/^https?:\/\//i.test(documentPath)) return documentPath;

  let normalizedPath = `${documentPath}`;
  // Handle historical absolute filesystem paths such as
  // /opt/render/project/src/backend/uploads/documents/<file>.
  if (normalizedPath.includes('/uploads/')) {
    normalizedPath = normalizedPath.slice(normalizedPath.indexOf('/uploads/'));
  } else if (normalizedPath.startsWith('uploads/')) {
    normalizedPath = `/${normalizedPath}`;
  } else if (!normalizedPath.startsWith('/')) {
    return documentPath;
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
      Booking.find({
        status: { $in: ['searching', 'accepted', 'driver_arriving', 'in_progress'] }
      })
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
        bookings: liveBookings.map((booking) => {
          const ser = serializeAdminBooking(booking);
          return {
            id: ser._id,
            bookingId: ser.bookingId,
            status: ser.status,
            vehicleType: ser.vehicleType,
            estimatedFare: ser.estimatedFare,
            estimatedDistance: ser.estimatedDistance,
            platformFee: ser.platformFee,
            driverPayout: ser.driverPayout,
            platformFeeStatus: ser.platformFeeStatus,
            pickup: ser.pickup?.address,
            dropoff: ser.dropoff?.address,
            customer: ser.customer
              ? {
                  name: ser.customer.name,
                  phone: ser.customer.phone
                }
              : null,
            driver: ser.driver
              ? {
                  name: ser.driver.name,
                  phone: ser.driver.phone,
                  vehicleNumber: ser.driver.vehicleNumber
                }
              : null,
            updatedAt: ser.updatedAt
          };
        }),
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
    const { status, page = 1, limit = 20, q } = req.query;
    const base = {};
    if (status) base.approvalStatus = status;
    const trimmed = `${q || ''}`.trim();
    let query = { ...base };
    if (trimmed.length >= 2) {
      const rx = buildTextRegex(trimmed);
      const search = {
        $or: [
          { name: rx },
          { phone: rx },
          { vehicleNumber: rx },
          { drivingLicense: rx },
          { vehicleModel: rx }
        ]
      };
      query = mergeStatusAndSearch(base, search);
    }
    const lim = Math.min(100, Math.max(1, parseInt(limit, 10) || 20));
    const pg = Math.max(1, parseInt(page, 10) || 1);
    const drivers = await Driver.find(query)
      .populate('user', 'name phone createdAt')
      .sort({ createdAt: -1 })
      .skip((pg - 1) * lim)
      .limit(lim);
    const total = await Driver.countDocuments(query);
    res.json({
      success: true,
      drivers: drivers.map((driver) => normalizeDriverDocuments(req, driver)),
      total,
      pages: Math.ceil(total / lim)
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
    const bookings = await Booking.find({ driver: driver._id })
      .sort({ createdAt: -1 })
      .limit(80)
      .populate('customer', 'name phone')
      .lean();
    res.json({
      success: true,
      driver: normalizeDriverDocuments(req, driver),
      bookings: bookings.map(serializeAdminBooking)
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/user/:id — customer profile + recent bookings
router.get('/user/:id', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const user = await User.findById(req.params.id).lean();
    if (!user || user.role !== 'customer') {
      return res.status(404).json({ error: 'Customer not found' });
    }
    const bookings = await Booking.find({ customer: user._id })
      .sort({ createdAt: -1 })
      .limit(80)
      .populate({ path: 'driver', select: 'name phone vehicleNumber vehicleType' })
      .lean();
    res.json({
      success: true,
      user,
      bookings: bookings.map(serializeAdminBooking)
    });
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
    const { page = 1, limit = 20, q } = req.query;
    const base = { role: 'customer' };
    const trimmed = `${q || ''}`.trim();
    let query = { ...base };
    if (trimmed.length >= 1) {
      const rx = buildTextRegex(trimmed);
      query = mergeStatusAndSearch(base, { $or: [{ name: rx }, { phone: rx }] });
    }
    const lim = Math.min(100, Math.max(1, parseInt(limit, 10) || 20));
    const pg = Math.max(1, parseInt(page, 10) || 1);
    const users = await User.find(query)
      .sort({ createdAt: -1 })
      .skip((pg - 1) * lim)
      .limit(lim);
    const total = await User.countDocuments(query);
    res.json({ success: true, users, total });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/bookings
router.get('/bookings', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const { status, page = 1, limit = 20, q } = req.query;
    const base = {};
    if (status) base.status = status;
    const search = await bookingSearchConditions(q);
    const query = mergeStatusAndSearch(base, search);
    const lim = Math.min(100, Math.max(1, parseInt(limit, 10) || 20));
    const pg = Math.max(1, parseInt(page, 10) || 1);
    const bookings = await Booking.find(query)
      .populate('customer', 'name phone')
      .populate({ path: 'driver', populate: { path: 'user', select: 'name phone' } })
      .sort({ createdAt: -1 })
      .skip((pg - 1) * lim)
      .limit(lim);
    const total = await Booking.countDocuments(query);
    res.json({
      success: true,
      bookings: bookings.map(serializeAdminBooking),
      total
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/search — quick lookup across customers, drivers, bookings
router.get('/search', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const q = `${req.query.q || ''}`.trim();
    if (q.length < 2) {
      return res.json({ success: true, users: [], drivers: [], bookings: [] });
    }
    const rx = buildTextRegex(q);
    const bookingMatch = await bookingSearchConditions(q);
    const [users, drivers, bookingsRaw] = await Promise.all([
      User.find({ role: 'customer', $or: [{ name: rx }, { phone: rx }] })
        .sort({ createdAt: -1 })
        .limit(10)
        .select('name phone isActive createdAt')
        .lean(),
      Driver.find({
        $or: [{ name: rx }, { phone: rx }, { vehicleNumber: rx }, { drivingLicense: rx }]
      })
        .sort({ createdAt: -1 })
        .limit(10)
        .select('name phone vehicleNumber vehicleType approvalStatus')
        .lean(),
      bookingMatch
        ? Booking.find(bookingMatch)
            .sort({ updatedAt: -1 })
            .limit(10)
            .populate('customer', 'name phone')
            .populate({ path: 'driver', populate: { path: 'user', select: 'name phone' } })
            .lean()
        : Promise.resolve([])
    ]);
    res.json({
      success: true,
      users,
      drivers,
      bookings: bookingsRaw.map(serializeAdminBooking)
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/commission-board — platform fee totals (completed trips)
router.get('/commission-board', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const pct = commissionPercent();
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const effPlatform = {
      $cond: [
        { $gt: [{ $ifNull: ['$platformFee', 0] }, 0] },
        '$platformFee',
        {
          $round: [
            { $divide: [{ $multiply: [{ $ifNull: ['$estimatedFare', 0] }, pct] }, 100] },
            0
          ]
        }
      ]
    };
    const [summary, byStatus, last30Days, activeTrips] = await Promise.all([
      Booking.aggregate([
        { $match: { status: 'completed' } },
        { $addFields: { effPlatform } },
        {
          $group: {
            _id: null,
            trips: { $sum: 1 },
            totalCustomerPaid: { $sum: { $ifNull: ['$estimatedFare', 0] } },
            totalPlatform: { $sum: '$effPlatform' }
          }
        },
        {
          $project: {
            _id: 0,
            trips: 1,
            totalCustomerPaid: 1,
            totalPlatform: 1,
            totalDriverPayout: { $subtract: ['$totalCustomerPaid', '$totalPlatform'] }
          }
        }
      ]),
      Booking.aggregate([
        { $match: { status: 'completed' } },
        { $addFields: { effPlatform } },
        {
          $group: {
            _id: '$platformFeeStatus',
            count: { $sum: 1 },
            platformTotal: { $sum: '$effPlatform' }
          }
        }
      ]),
      Booking.aggregate([
        {
          $match: {
            status: 'completed',
            completedAt: { $gte: thirtyDaysAgo }
          }
        },
        { $addFields: { effPlatform } },
        {
          $group: {
            _id: { $dateToString: { format: '%Y-%m-%d', date: '$completedAt' } },
            trips: { $sum: 1 },
            platformFee: { $sum: '$effPlatform' },
            customerPaid: { $sum: { $ifNull: ['$estimatedFare', 0] } }
          }
        },
        { $sort: { _id: 1 } }
      ]),
      Booking.countDocuments({
        status: { $in: ['searching', 'accepted', 'driver_arriving', 'in_progress'] }
      })
    ]);

    res.json({
      success: true,
      commissionPercent: pct,
      summary: summary[0] || {
        trips: 0,
        totalCustomerPaid: 0,
        totalPlatform: 0,
        totalDriverPayout: 0
      },
      byStatus,
      last30Days,
      activeTrips
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/admin/booking/:id/cancel — force-cancel any non-terminal trip (ops)
router.post('/booking/:id/cancel', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const raw = `${req.params.id || ''}`.trim();
    const { reason } = req.body || {};
    if (!raw) return res.status(400).json({ error: 'Booking id required' });

    let booking = null;
    if (mongoose.Types.ObjectId.isValid(raw) && raw.length === 24) {
      booking = await Booking.findById(raw);
    }
    if (!booking) {
      booking = await Booking.findOne({ bookingId: raw });
    }
    if (!booking) return res.status(404).json({ error: 'Booking not found' });
    if (['completed', 'cancelled'].includes(booking.status)) {
      return res.status(400).json({ error: 'Booking is already completed or cancelled' });
    }

    const previousStatus = booking.status;
    booking.status = 'cancelled';
    booking.cancelledBy = 'admin';
    booking.cancellationReason = reason || 'Cancelled by admin';

    const driverRef = booking.driver?._id ?? booking.driver;
    if (driverRef) {
      const driver = await Driver.findById(driverRef);
      if (driver) {
        driver.isAvailable = true;
        await driver.save();
      }
    }

    await booking.save();
    logAuditEvent({
      req,
      action: 'admin_cancel_booking',
      entityType: 'booking',
      entityId: booking._id,
      metadata: {
        reason: booking.cancellationReason,
        previousStatus
      }
    });

    if (req.io) {
      req.io.to(`booking_${booking._id}`).emit('booking_cancelled', {
        bookingId: booking._id,
        by: 'admin'
      });
    }

    res.json({ success: true, message: 'Booking cancelled', booking: serializeAdminBooking(booking) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/admin/user/:id/toggle  (keep after GET /user/:id — same param pattern)
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
