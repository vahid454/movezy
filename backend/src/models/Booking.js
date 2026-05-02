const mongoose = require('mongoose');

const bookingSchema = new mongoose.Schema({
  bookingId: { type: String, unique: true, required: true },
  customer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  driver: { type: mongoose.Schema.Types.ObjectId, ref: 'Driver' },
  vehicleType: {
    type: String,
    enum: ['bike', 'auto', 'mini_truck', 'tempo', 'truck', 'pickup'],
    required: true
  },
  pickup: {
    address: { type: String, required: true },
    location: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], required: true } // [lng, lat]
    }
  },
  dropoff: {
    address: { type: String, required: true },
    location: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], required: true }
    }
  },
  description: { type: String }, // What needs to be transported
  estimatedDistance: { type: Number }, // in km
  estimatedFare: { type: Number },   // in INR
  status: {
    type: String,
    enum: [
      'searching',    // Looking for driver
      'accepted',     // Driver accepted
      'driver_arriving', // Driver en route to pickup
      'in_progress',  // Trip started
      'completed',    // Trip done
      'cancelled'     // Cancelled
    ],
    default: 'searching'
  },
  cancelledBy: { type: String, enum: ['customer', 'driver', 'admin', 'system'] },
  cancellationReason: { type: String },
  acceptedAt: { type: Date },
  startedAt: { type: Date },
  completedAt: { type: Date },
  customerRating: { type: Number, min: 1, max: 5 },
  customerReview: { type: String },
  driverRating: { type: Number, min: 1, max: 5 },
  searchRadius: { type: Number, default: 5000 }, // meters, increases over time
  notifiedDrivers: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Driver' }],
  rejectedByDrivers: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Driver' }],
  createBookingIdempotencyKey: { type: String, trim: true },
  acceptedByDriverRequestId: { type: String, trim: true }
}, { timestamps: true });

// No geospatial index on pickup: nearby-driver matching uses Haversine in code.
// If an older deploy created `pickup.location` 2dsphere in MongoDB, drop it in
// Atlas / shell when convenient; it is unused by current queries.

bookingSchema.index({ customer: 1, status: 1 });
bookingSchema.index({ driver: 1, status: 1 });
bookingSchema.index({ createdAt: -1 });
bookingSchema.index(
  { customer: 1, createBookingIdempotencyKey: 1 },
  {
    unique: true,
    partialFilterExpression: { createBookingIdempotencyKey: { $type: 'string' } }
  }
);

module.exports = mongoose.model('Booking', bookingSchema);
