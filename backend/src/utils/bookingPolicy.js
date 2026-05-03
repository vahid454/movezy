const STRICT_POLICY_ENABLED = process.env.ENABLE_STRICT_BOOKING_POLICY === 'true';

const BOOKING_STATUSES = Object.freeze({
  SEARCHING: 'searching',
  ACCEPTED: 'accepted',
  DRIVER_ARRIVING: 'driver_arriving',
  IN_PROGRESS: 'in_progress',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled'
});

const ALLOWED_TRANSITIONS = Object.freeze({
  [BOOKING_STATUSES.SEARCHING]: [BOOKING_STATUSES.ACCEPTED, BOOKING_STATUSES.CANCELLED],
  [BOOKING_STATUSES.ACCEPTED]: [BOOKING_STATUSES.DRIVER_ARRIVING, BOOKING_STATUSES.IN_PROGRESS, BOOKING_STATUSES.CANCELLED],
  [BOOKING_STATUSES.DRIVER_ARRIVING]: [BOOKING_STATUSES.IN_PROGRESS, BOOKING_STATUSES.CANCELLED],
  [BOOKING_STATUSES.IN_PROGRESS]: [BOOKING_STATUSES.COMPLETED, BOOKING_STATUSES.CANCELLED],
  [BOOKING_STATUSES.COMPLETED]: [],
  [BOOKING_STATUSES.CANCELLED]: []
});

const canTransitionStatus = (currentStatus, nextStatus) => {
  if (!currentStatus || !nextStatus) return false;
  return (ALLOWED_TRANSITIONS[currentStatus] || []).includes(nextStatus);
};

const enforceTransitionOrBypass = (currentStatus, nextStatus) => {
  if (!STRICT_POLICY_ENABLED) return { allowed: true };

  if (!canTransitionStatus(currentStatus, nextStatus)) {
    return {
      allowed: false,
      message: `Cannot move booking from ${currentStatus} to ${nextStatus}`
    };
  }

  return { allowed: true };
};

const canAccessBooking = ({ booking, userId, role, driverId }) => {
  if (!booking || !userId || !role) return false;
  if (role === 'admin') return true;

  if (role === 'customer') {
    return booking.customer && booking.customer.toString() === userId.toString();
  }

  if (role === 'driver') {
    if (!driverId) return false;
    return booking.driver && booking.driver.toString() === driverId.toString();
  }

  return false;
};

module.exports = {
  BOOKING_STATUSES,
  canAccessBooking,
  canTransitionStatus,
  enforceTransitionOrBypass,
  STRICT_POLICY_ENABLED
};
