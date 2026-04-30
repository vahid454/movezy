const { randomUUID } = require('crypto');

const attachRequestContext = (req, res, next) => {
  const incomingRequestId = req.headers['x-request-id'];
  const requestId = typeof incomingRequestId === 'string' && incomingRequestId.trim()
    ? incomingRequestId.trim()
    : randomUUID();

  req.requestId = requestId;
  res.setHeader('x-request-id', requestId);

  const startedAt = Date.now();
  res.on('finish', () => {
    if (process.env.ENABLE_REQUEST_LOGS !== 'true') return;

    const elapsedMs = Date.now() - startedAt;
    console.log(JSON.stringify({
      type: 'request_log',
      requestId,
      method: req.method,
      path: req.originalUrl,
      statusCode: res.statusCode,
      elapsedMs,
      userId: req.userId ? String(req.userId) : null,
      role: req.user?.role || null
    }));
  });

  next();
};

module.exports = { attachRequestContext };
