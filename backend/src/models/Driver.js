const mongoose = require('mongoose');

const driverSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, unique: true },
  name: { type: String, required: true },
  phone: { type: String, required: true },
  drivingLicense: { type: String, required: true },
  vehicleNumber: { type: String, required: true, uppercase: true },
  vehicleType: {
    type: String,
    enum: ['bike', 'auto', 'mini_truck', 'tempo', 'truck', 'pickup'],
    required: true
  },
  vehicleModel: { type: String },
  documents: {
    licenseImage: { type: String },
    vehicleRC: { type: String },
    insurance: { type: String },
    profilePhoto: { type: String }
  },
  approvalStatus: {
    type: String,
    enum: ['pending', 'approved', 'rejected'],
    default: 'pending'
  },
  rejectionReason: { type: String },
  isOnline: { type: Boolean, default: false },
  isAvailable: { type: Boolean, default: true }, // false when on a trip
  location: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], default: [0, 0] }
  },
  rating: { type: Number, default: 5.0, min: 1, max: 5 },
  totalTrips: { type: Number, default: 0 },
  totalEarnings: { type: Number, default: 0 },
  reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  reviewedAt: { type: Date }
}, { timestamps: true });

driverSchema.index({ location: '2dsphere' });
driverSchema.index({ approvalStatus: 1, isOnline: 1, isAvailable: 1 });

module.exports = mongoose.model('Driver', driverSchema);
