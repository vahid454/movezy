const express = require('express');
const router = express.Router();
const { body, validationResult } = require('express-validator');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const OTP = require('../models/OTP');

// Helper: Generate OTP
const generateOTP = () => {
  if (process.env.OTP_DEV_MODE === 'true') return process.env.OTP_DEV_CODE || '123456';
  return Math.floor(100000 + Math.random() * 900000).toString();
};

// Helper: Send OTP via Twilio
const sendOTP = async (phone, otp) => {
  if (process.env.OTP_DEV_MODE === 'true') {
    console.log(`[DEV] OTP for ${phone}: ${otp}`);
    return true;
  }
  const twilio = require('twilio')(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
  await twilio.messages.create({
    body: `Your Movezy OTP is: ${otp}. Valid for 5 minutes.`,
    from: process.env.TWILIO_PHONE_NUMBER,
    to: phone
  });
  return true;
};

// POST /api/auth/send-otp
router.post('/send-otp',
  [body('phone').isMobilePhone().withMessage('Invalid phone number')],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    try {
      const { phone } = req.body;
      const otp = generateOTP();
      const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes

      await OTP.findOneAndUpdate(
        { phone },
        { otp, expiresAt, verified: false, attempts: 0 },
        { upsert: true, new: true }
      );

      await sendOTP(phone, otp);
      res.json({ success: true, message: 'OTP sent successfully', devOtp: process.env.OTP_DEV_MODE === 'true' ? otp : undefined });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  }
);

// POST /api/auth/verify-otp - Customer login/register
router.post('/verify-otp',
  [
    body('phone').isMobilePhone(),
    body('otp').isLength({ min: 6, max: 6 }),
    body('name').optional().trim().isLength({ min: 2 })
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    try {
      const { phone, otp, name, fcmToken } = req.body;

      const otpRecord = await OTP.findOne({ phone });
      if (!otpRecord) return res.status(400).json({ error: 'OTP not found. Request a new one.' });
      if (otpRecord.verified) return res.status(400).json({ error: 'OTP already used.' });
      if (new Date() > otpRecord.expiresAt) return res.status(400).json({ error: 'OTP expired.' });
      if (otpRecord.attempts >= 3) return res.status(400).json({ error: 'Too many attempts. Request a new OTP.' });
      if (otpRecord.otp !== otp) {
        otpRecord.attempts += 1;
        await otpRecord.save();
        return res.status(400).json({ error: 'Invalid OTP.' });
      }

      otpRecord.verified = true;
      await otpRecord.save();

      let user = await User.findOne({ phone });
      const isNewUser = !user;

      if (!user) {
        if (!name) return res.status(400).json({ error: 'Name required for new users.' });
        user = await User.create({ name, phone, role: 'customer', fcmToken });
      } else {
        if (fcmToken) { user.fcmToken = fcmToken; await user.save(); }
      }

      const token = jwt.sign({ userId: user._id, role: user.role }, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRE || '7d' });

      res.json({ success: true, token, user: { id: user._id, name: user.name, phone: user.phone, role: user.role }, isNewUser });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  }
);

// POST /api/auth/driver-verify-otp - Driver OTP verify (after registration)
router.post('/driver-verify-otp',
  [body('phone').isMobilePhone(), body('otp').isLength({ min: 6, max: 6 })],
  async (req, res) => {
    try {
      const { phone, otp, fcmToken } = req.body;
      const otpRecord = await OTP.findOne({ phone });
      if (!otpRecord || otpRecord.verified || new Date() > otpRecord.expiresAt || otpRecord.otp !== otp) {
        return res.status(400).json({ error: 'Invalid or expired OTP.' });
      }

      otpRecord.verified = true;
      await otpRecord.save();

      const user = await User.findOne({ phone, role: 'driver' });
      if (!user) return res.status(404).json({ error: 'Driver account not found. Please register first.' });

      if (fcmToken) { user.fcmToken = fcmToken; await user.save(); }

      const token = jwt.sign({ userId: user._id, role: user.role }, process.env.JWT_SECRET, { expiresIn: '7d' });
      res.json({ success: true, token, user: { id: user._id, name: user.name, phone: user.phone, role: user.role } });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  }
);

// POST /api/auth/admin-login
router.post('/admin-login',
  [body('secretKey').notEmpty()],
  async (req, res) => {
    try {
      const { secretKey, phone } = req.body;
      if (secretKey !== process.env.ADMIN_SECRET_KEY) return res.status(401).json({ error: 'Invalid admin key' });

      let admin = await User.findOne({ role: 'admin' });
      if (!admin) {
        admin = await User.create({ name: 'Admin', phone: phone || '+910000000000', role: 'admin' });
      }

      const token = jwt.sign({ userId: admin._id, role: 'admin' }, process.env.JWT_SECRET, { expiresIn: '24h' });
      res.json({ success: true, token, user: { id: admin._id, name: admin.name, role: 'admin' } });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  }
);

module.exports = router;
