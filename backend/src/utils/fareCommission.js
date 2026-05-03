'use strict';

/** Percent of customer total retained by Movezy (driver gets the remainder). */
const commissionPercent = () => {
  const n = Number(process.env.MOVEZY_COMMISSION_PERCENT || 10);
  if (!Number.isFinite(n) || n < 0) return 10;
  return Math.min(90, n);
};

/**
 * @param {number} customerTotalInr - rounded INR the customer pays (incl. booking fee in fare formula).
 * @returns {{ customerTotal: number, platformFee: number, driverPayout: number }}
 */
const splitCustomerFare = (customerTotalInr) => {
  const customerTotal = Math.max(0, Math.round(Number(customerTotalInr) || 0));
  const pct = commissionPercent();
  const platformFee = Math.round((customerTotal * pct) / 100);
  const driverPayout = Math.max(0, customerTotal - platformFee);
  return { customerTotal, platformFee, driverPayout };
};

/**
 * Ensures lean/plain booking objects include platformFee + driverPayout for API/socket payloads.
 * @param {object} b
 */
const attachFareSplit = (b) => {
  if (!b || typeof b !== 'object') return b;
  const t = Math.round(Number(b.estimatedFare) || 0);
  if (b.platformFee != null && b.driverPayout != null) return b;
  const s = splitCustomerFare(t);
  return {
    ...b,
    platformFee: b.platformFee ?? s.platformFee,
    driverPayout: b.driverPayout ?? s.driverPayout
  };
};

const markCommissionDue = (booking) => {
  if (!booking) return;
  booking.platformFeeStatus = 'due';
};

/**
 * Customer cancel fee (INR) by trip phase. Env-tunable; capped by estimated fare.
 * @param {{ status?: string, estimatedFare?: number }} booking
 */
const computeCustomerCancellationFeeInr = (booking) => {
  const fare = Math.max(0, Math.round(Number(booking?.estimatedFare) || 0));
  const s = `${booking?.status || ''}`;
  if (s === 'searching') {
    const flat = Math.max(0, Number(process.env.CUSTOMER_CANCEL_FEE_SEARCHING_FLAT || 0));
    return Math.min(fare, flat);
  }
  if (s === 'accepted' || s === 'driver_arriving') {
    const pct = Number(process.env.CUSTOMER_CANCEL_FEE_AFTER_ACCEPT_PERCENT || 25);
    const floor = Number(process.env.CUSTOMER_CANCEL_FEE_AFTER_ACCEPT_MIN || 50);
    return Math.min(fare, Math.max(floor, Math.round((fare * pct) / 100)));
  }
  if (s === 'in_progress') {
    const pct = Number(process.env.CUSTOMER_CANCEL_FEE_MID_TRIP_PERCENT || 40);
    const floor = Number(process.env.CUSTOMER_CANCEL_FEE_MID_TRIP_MIN || 99);
    return Math.min(fare, Math.max(floor, Math.round((fare * pct) / 100)));
  }
  return 0;
};

const flagCommissionRisk = (booking, code, note) => {
  if (!booking || !code) return;
  booking.commissionRiskFlags = booking.commissionRiskFlags || [];
  booking.commissionRiskFlags.push({
    code,
    note,
    createdAt: new Date()
  });
};

module.exports = {
  commissionPercent,
  splitCustomerFare,
  attachFareSplit,
  markCommissionDue,
  flagCommissionRisk,
  computeCustomerCancellationFeeInr
};
