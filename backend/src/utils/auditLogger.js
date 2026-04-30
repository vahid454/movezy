const AUDIT_LOGS_ENABLED = process.env.ENABLE_AUDIT_LOGS === 'true';

const logAuditEvent = ({ req, action, entityType, entityId, metadata = {} }) => {
  if (!AUDIT_LOGS_ENABLED) return;

  console.log(JSON.stringify({
    type: 'audit_log',
    requestId: req?.requestId || null,
    actorUserId: req?.userId ? String(req.userId) : null,
    actorRole: req?.user?.role || null,
    action,
    entityType,
    entityId: entityId ? String(entityId) : null,
    metadata,
    timestamp: new Date().toISOString()
  }));
};

module.exports = { logAuditEvent };
