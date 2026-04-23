const express = require('express');
const router = express.Router();
const Booking = require('../models/Booking');
const { authenticate } = require('../middleware/auth');

// GET /api/booking/:id/status - Poll booking status
router.get('/:id/status', authenticate, async (req, res) => {
  try {
    const booking = await Booking.findById(req.params.id)
      .populate('customer', 'name phone')
      .populate({ path: 'driver', populate: { path: 'user', select: 'name phone' } });

    if (!booking) return res.status(404).json({ error: 'Booking not found' });
    res.json({ success: true, booking });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/booking/driver/active - Driver's active booking
router.get('/driver/active', authenticate, async (req, res) => {
  try {
    const Driver = require('../models/Driver');
    const driver = await Driver.findOne({ user: req.userId });
    if (!driver) return res.status(404).json({ error: 'Driver not found' });

    const booking = await Booking.findOne({
      driver: driver._id,
      status: { $in: ['accepted', 'driver_arriving', 'in_progress'] }
    }).populate('customer', 'name phone location');

    res.json({ success: true, booking });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
