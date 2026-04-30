const IDEMPOTENCY_ENABLED = process.env.ENABLE_IDEMPOTENCY_KEYS === 'true';

const getIdempotencyKey = (req) => {
  const rawKey = req.headers['x-idempotency-key'];
  if (typeof rawKey !== 'string') return null;

  const normalizedKey = rawKey.trim();
  if (!normalizedKey || normalizedKey.length > 100) return null;

  return normalizedKey;
};

module.exports = {
  IDEMPOTENCY_ENABLED,
  getIdempotencyKey
};
