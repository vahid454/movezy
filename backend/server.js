const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const mongoose = require('mongoose');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
require('dotenv').config();

const authRoutes = require('./src/routes/auth');
const customerRoutes = require('./src/routes/customer');
const driverRoutes = require('./src/routes/driver');
const bookingRoutes = require('./src/routes/booking');
const adminRoutes = require('./src/routes/admin');
const { setupSocketHandlers } = require('./src/utils/socketHandler');
const { attachRequestContext } = require('./src/middleware/requestContext');
const {
  createApiLimiter,
  createAuthLimiter,
  createBookingActionLimiter,
  createLocationUpdateLimiter
} = require('./src/middleware/rateLimits');
const { dropLegacyBookingGeoIndexes } = require('./src/utils/bookingIndexes');
const Booking = require('./src/models/Booking');

const app = express();
const server = http.createServer(app);
const corsOrigins = (process.env.CORS_ORIGINS || '').split(',').map((origin) => origin.trim()).filter(Boolean);
const io = socketIo(server, {
  cors: {
    origin: corsOrigins.length ? corsOrigins : '*',
    methods: ['GET', 'POST', 'PUT', 'PATCH'],
    credentials: true
  }
});

// Middleware
app.use(helmet());
app.set('trust proxy', 1);
app.use(cors({
  origin: corsOrigins.length ? corsOrigins : '*',
  credentials: true
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(morgan('combined'));
app.use(attachRequestContext);

// Rate limiting
app.use('/api/', createApiLimiter());
app.use('/api/auth', createAuthLimiter());
app.use('/api/customer/create-booking', createBookingActionLimiter());
app.use('/api/driver/respond-booking', createBookingActionLimiter());
app.use('/api/customer/update-location', createLocationUpdateLimiter());
app.use('/api/driver/update-location', createLocationUpdateLimiter());

// Make io accessible to routes
app.use((req, res, next) => {
  req.io = io;
  next();
});

// Static files for document uploads
app.use('/uploads', express.static('uploads'));

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/customer', customerRoutes);
app.use('/api/driver', driverRoutes);
app.use('/api/booking', bookingRoutes);
app.use('/api/admin', adminRoutes);

// Health check
app.get('/health', (req, res) => res.json({ status: 'OK', timestamp: new Date() }));

// Socket.io setup
setupSocketHandlers(io);

// Error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error', message: err.message });
});

const PORT = process.env.PORT || 3000;
const startServer = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/movezy');
    console.log('✅ MongoDB connected');
    await dropLegacyBookingGeoIndexes(mongoose.connection);
    try {
      await Booking.syncIndexes();
    } catch (err) {
      console.warn('Booking.syncIndexes:', err.message);
    }
    server.listen(PORT, () => {
      console.log(`🚀 Movezy Server running on port ${PORT}`);
    });
  } catch (err) {
    console.error('❌ MongoDB error:', err);
    process.exit(1);
  }
};

const gracefulShutdown = async (signal) => {
  console.log(`Received ${signal}. Starting graceful shutdown...`);
  server.close(async () => {
    await mongoose.connection.close();
    process.exit(0);
  });
};

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

startServer();

module.exports = { app, io };
