const rateLimit = require('express-rate-limit');

const toPositiveNumber = (value, fallbackValue) => {
  const parsedValue = Number(value);
  return Number.isFinite(parsedValue) && parsedValue > 0 ? parsedValue : fallbackValue;
};

const createLimiter = ({ windowMs, max, message }) => rateLimit({
  windowMs,
  max,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: message }
});

const createApiLimiter = () => createLimiter({
  windowMs: 15 * 60 * 1000,
  max: toPositiveNumber(process.env.RATE_LIMIT_MAX, 100),
  message: 'Too many requests, please try again later.'
});

const createAuthLimiter = () => createLimiter({
  windowMs: 15 * 60 * 1000,
  max: toPositiveNumber(process.env.AUTH_RATE_LIMIT_MAX, 25),
  message: 'Too many auth attempts. Please wait before retrying.'
});

const createBookingActionLimiter = () => createLimiter({
  windowMs: 10 * 60 * 1000,
  max: toPositiveNumber(process.env.BOOKING_ACTION_RATE_LIMIT_MAX, 40),
  message: 'Too many booking actions. Please slow down and retry.'
});

const createLocationUpdateLimiter = () => createLimiter({
  windowMs: 60 * 1000,
  max: toPositiveNumber(process.env.LOCATION_RATE_LIMIT_MAX, 90),
  message: 'Location updates are too frequent. Please retry shortly.'
});

module.exports = {
  createApiLimiter,
  createAuthLimiter,
  createBookingActionLimiter,
  createLocationUpdateLimiter
};
