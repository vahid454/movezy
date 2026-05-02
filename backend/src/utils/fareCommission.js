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

module.exports = {
  commissionPercent,
  splitCustomerFare,
  attachFareSplit
};
