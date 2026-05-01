const express = require('express');
const router = express.Router();
const { body, validationResult } = require('express-validator');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const Driver = require('../models/Driver');
const OTP = require('../models/OTP');

let firebaseAdmin = null;

const getFirebaseAdmin = () => {
  if (firebaseAdmin) return firebaseAdmin;
  try {
    const admin = require('firebase-admin');
    if (!admin.apps.length) {
      const projectId = process.env.FIREBASE_PROJECT_ID;
      const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
      const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');

      if (!projectId || !clientEmail || !privateKey) {
        throw new Error('Firebase Admin credentials are missing');
      }

      admin.initializeApp({
        credential: admin.credential.cert({
          projectId,
          clientEmail,
          privateKey
        })
      });
    }
    firebaseAdmin = admin;
    return admin;
  } catch (error) {
    return null;
  }
};

// Helper: Generate OTP
const generateOTP = () => {
  if (process.env.OTP_DEV_MODE === 'true') return process.env.OTP_DEV_CODE;
  return Math.floor(100000 + Math.random() * 900000).toString();
};

// Helper: Send OTP via Twilio
const sendOTP = async (phone, otp) => {
  if (process.env.OTP_DEV_MODE === 'true') {
    console.log(`[DEV] OTP for ${phone}: ${otp}`);
    return true;
  }
  try {
    const twilio = require('twilio')(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
    await twilio.messages.create({
      body: `Your Movezy OTP is: ${otp}. Valid for 5 minutes.`,
      from: process.env.TWILIO_PHONE_NUMBER,
      to: phone
    });
    return true;
  } catch (error) {
    const twilioDebug = {
      type: 'twilio_send_otp_error',
      message: error?.message || 'Unknown Twilio error',
      code: error?.code || null,
      status: error?.status || null,
      moreInfo: error?.moreInfo || null,
      to: phone,
      from: process.env.TWILIO_PHONE_NUMBER || null
    };
    console.error(JSON.stringify(twilioDebug));
    throw new Error(`OTP delivery failed: ${twilioDebug.message}`);
  }
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
      if (!otp) {
        return res.status(500).json({ error: 'OTP_DEV_CODE is required when OTP_DEV_MODE is enabled.' });
      }
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

// POST /api/auth/firebase-exchange - Firebase verified login/register
router.post('/firebase-exchange',
  [
    body('idToken').notEmpty().withMessage('idToken is required'),
    body('isDriver').optional().isBoolean(),
    body('name').optional().trim().isLength({ min: 2 })
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    try {
      const admin = getFirebaseAdmin();
      if (!admin) {
        return res.status(500).json({ error: 'Firebase auth is not configured on server.' });
      }

      const { idToken, name, fcmToken } = req.body;
      const isDriver = req.body.isDriver === true;
      const decoded = await admin.auth().verifyIdToken(idToken);
      const phone = decoded.phone_number;

      if (!phone) {
        return res.status(400).json({ error: 'Phone number not found in Firebase token.' });
      }

      let user = await User.findOne({ phone });
      const isNewUser = !user;

      if (!user) {
        if (isDriver) {
          return res.status(404).json({ error: 'Driver account not found. Please register first.' });
        }
        if (!name) {
          return res.status(400).json({ error: 'Name required for new users.' });
        }
        user = await User.create({ name, phone, role: 'customer', fcmToken });
      } else if (fcmToken) {
        user.fcmToken = fcmToken;
        await user.save();
      }

      if (isDriver) {
        if (user.role !== 'driver') {
          return res.status(403).json({ error: 'This phone is not registered as a driver account.' });
        }

        const driverProfile = await Driver.findOne({ user: user._id }).select('approvalStatus rejectionReason');
        if (!driverProfile) {
          return res.status(404).json({ error: 'Driver profile not found. Please register again.' });
        }
        if (driverProfile.approvalStatus === 'pending') {
          return res.status(403).json({
            error: 'Thanks for registering. Your profile is under review. Please wait while our backend team processes your approval.',
            approvalStatus: 'pending'
          });
        }
        if (driverProfile.approvalStatus === 'rejected') {
          return res.status(403).json({
            error: `Your profile was not approved yet. Reason: ${driverProfile.rejectionReason || 'Documents need corrections'}. Please update and re-apply.`,
            approvalStatus: 'rejected'
          });
        }
      }

      const token = jwt.sign(
        { userId: user._id, role: user.role },
        process.env.JWT_SECRET,
        { expiresIn: process.env.JWT_EXPIRE || '7d' }
      );

      return res.json({
        success: true,
        token,
        user: { id: user._id, name: user.name, phone: user.phone, role: user.role },
        isNewUser
      });
    } catch (err) {
      return res.status(401).json({ error: 'Invalid Firebase token.' });
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

      const driverProfile = await Driver.findOne({ user: user._id }).select('approvalStatus rejectionReason');
      if (!driverProfile) {
        return res.status(404).json({ error: 'Driver profile not found. Please register again.' });
      }
      if (driverProfile.approvalStatus === 'pending') {
        return res.status(403).json({
          error: 'Thanks for registering. Your profile is under review. Please wait while our backend team processes your approval.',
          approvalStatus: 'pending'
        });
      }
      if (driverProfile.approvalStatus === 'rejected') {
        return res.status(403).json({
          error: `Your profile was not approved yet. Reason: ${driverProfile.rejectionReason || 'Documents need corrections'}. Please update and re-apply.`,
          approvalStatus: 'rejected'
        });
      }

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
