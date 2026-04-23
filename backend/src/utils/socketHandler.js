const jwt = require('jsonwebtoken');
const User = require('../models/User');
const Driver = require('../models/Driver');

const connectedUsers = new Map(); // userId -> socketId
const connectedDrivers = new Map(); // driverId -> socketId

const setupSocketHandlers = (io) => {
  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth.token;
      if (!token) return next(new Error('Authentication required'));
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      const user = await User.findById(decoded.userId);
      if (!user) return next(new Error('User not found'));
      socket.userId = user._id.toString();
      socket.userRole = user.role;
      next();
    } catch (err) {
      next(new Error('Invalid token'));
    }
  });

  io.on('connection', async (socket) => {
    console.log(`✅ Socket connected: ${socket.userId} (${socket.userRole})`);
    connectedUsers.set(socket.userId, socket.id);

    if (socket.userRole === 'driver') {
      const driver = await Driver.findOne({ user: socket.userId });
      if (driver) {
        socket.driverId = driver._id.toString();
        connectedDrivers.set(driver._id.toString(), socket.id);
        socket.join(`driver_${driver._id}`);
      }
    }

    // Join booking room
    socket.on('join_booking', (bookingId) => {
      socket.join(`booking_${bookingId}`);
    });

    // Driver location update
    socket.on('driver_location', async (data) => {
      const { latitude, longitude, bookingId } = data;
      if (bookingId) {
        io.to(`booking_${bookingId}`).emit('driver_location_update', { latitude, longitude });
      }
    });

    // Customer location update
    socket.on('customer_location', (data) => {
      const { latitude, longitude, bookingId } = data;
      if (bookingId) {
        io.to(`booking_${bookingId}`).emit('customer_location_update', { latitude, longitude });
      }
    });

    socket.on('disconnect', () => {
      connectedUsers.delete(socket.userId);
      if (socket.driverId) {
        connectedDrivers.delete(socket.driverId);
      }
      console.log(`❌ Socket disconnected: ${socket.userId}`);
    });
  });
};

module.exports = { setupSocketHandlers, connectedUsers, connectedDrivers };
