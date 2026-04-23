# ⚡ Movezy — Transport App (Like Rapido/Porter)
### Complete Production-Ready Source Code

---

## 📁 Project Structure

```
movezy/
├── backend/              ← Node.js + Express + MongoDB API
│   ├── server.js         ← Entry point
│   ├── src/
│   │   ├── routes/       ← auth, customer, driver, booking, admin
│   │   ├── models/       ← User, Driver, Booking, OTP schemas
│   │   ├── middleware/   ← JWT auth middleware
│   │   └── utils/        ← Socket.IO handler, push notifications
│   ├── .env.example
│   └── package.json
│
├── android/              ← Native Android (Kotlin + Jetpack)
│   └── app/src/main/
│       ├── java/com/movezy/
│       │   ├── ui/auth/     ← Login, OTP, Driver Registration
│       │   ├── ui/customer/ ← Home map, booking flow, history
│       │   ├── ui/driver/   ← Dashboard, accept trips, map
│       │   ├── data/        ← API service, models
│       │   ├── di/          ← Hilt dependency injection
│       │   ├── utils/       ← SessionManager, SocketManager
│       │   └── services/    ← FCM, Location tracking
│       └── res/             ← Layouts, themes, colors
│
└── admin-panel/          ← React.js Admin Dashboard
    ├── src/
    │   ├── pages/        ← Dashboard, Drivers, Users, Bookings, Login
    │   └── utils/        ← API client (axios)
    └── package.json
```

---

## 🚀 Quick Setup Guide

### Step 1: Prerequisites

```bash
# Required software
Node.js >= 18.x         → https://nodejs.org
MongoDB >= 6.x          → https://mongodb.com or use MongoDB Atlas
Android Studio Hedgehog → https://developer.android.com/studio
Java 17+
```

---

### Step 2: Backend Setup

```bash
cd movezy/backend

# Install dependencies
npm install

# Create environment file
cp .env.example .env

# Edit .env with your values:
nano .env
```

#### `.env` Configuration

```env
PORT=3000
NODE_ENV=development

# MongoDB (local or Atlas)
MONGODB_URI=mongodb://localhost:27017/movezy
# OR for Atlas:
# MONGODB_URI=mongodb+srv://user:pass@cluster.mongodb.net/movezy

# JWT (change this in production!)
JWT_SECRET=movezy_super_secret_change_me_in_production
JWT_EXPIRE=7d

# OTP (dev mode uses fixed OTP = 123456)
OTP_DEV_MODE=true
OTP_DEV_CODE=123456

# For production OTP, set up Twilio:
# TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxx
# TWILIO_AUTH_TOKEN=your_auth_token
# TWILIO_PHONE_NUMBER=+1234567890
# OTP_DEV_MODE=false

# Firebase (for push notifications)
# Get from Firebase Console → Project Settings → Service Account
# FIREBASE_PROJECT_ID=your-project-id
# FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
# FIREBASE_CLIENT_EMAIL=firebase-adminsdk@your-project.iam.gserviceaccount.com

# Admin
ADMIN_SECRET_KEY=your_admin_setup_secret
```

```bash
# Create uploads directory
mkdir -p uploads/documents

# Start the server
npm run dev          # Development (with nodemon auto-restart)
npm start            # Production

# Server runs at: http://localhost:3000
# Health check: http://localhost:3000/health
```

---

### Step 3: Admin Panel Setup

```bash
cd movezy/admin-panel

# Install dependencies
npm install

# Set API URL (if backend is not on localhost:3000)
# Create .env file:
echo "REACT_APP_API_URL=http://localhost:3000/api" > .env

# Start admin panel
npm start

# Opens at: http://localhost:3001

# To build for production:
npm run build
# Serve the build/ folder with nginx or any static host
```

#### Admin Login
1. Open http://localhost:3001
2. Enter the `ADMIN_SECRET_KEY` from your .env
3. Access: Dashboard, Drivers, Customers, Bookings

---

### Step 4: Android App Setup

#### 4a. Add Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Enable: **Maps SDK for Android**, **Places API**, **Geocoding API**
3. Create an API key → restrict to Android app
4. Open `android/app/src/main/res/values/strings.xml`
5. Replace `YOUR_GOOGLE_MAPS_API_KEY_HERE` with your key

#### 4b. Configure Firebase

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create project → Add Android app
3. Package name: `com.movezy`
4. Download `google-services.json`
5. Place it at: `android/app/google-services.json`
6. Copy server credentials to backend `.env`

#### 4c. Update Backend URL

Open `android/app/build.gradle` and update:
```groovy
buildConfigField "String", "BASE_URL", "\"http://YOUR_IP:3000/api/\""
buildConfigField "String", "SOCKET_URL", "\"http://YOUR_IP:3000\""
```

> ⚠️ Use your computer's local IP (e.g. `192.168.1.5`), not `localhost`, when testing on a real device.
> Use `10.0.2.2` for Android Emulator.

#### 4d. Build & Run

```bash
# Open Android Studio
# File → Open → select movezy/android/

# Wait for Gradle sync to complete
# Connect device or start emulator
# Click ▶ Run
```

---

## 🔄 App Flow

### Customer Flow
```
Launch → Splash → Login with phone+OTP → Home (Map)
→ Tap "Book Transport" → Select vehicle type
→ Enter pickup + dropoff → Confirm booking
→ See "Searching..." → Driver accepts → See driver on map
→ Trip starts → Trip completed → Rate driver
```

### Driver Flow
```
Register (name, phone, license, vehicle, docs)
→ Admin approves → Login with OTP
→ Home dashboard → Toggle ONLINE
→ New booking popup appears → Accept/Reject
→ Head to pickup → Start Trip → Complete Trip
```

### Admin Flow
```
Login with secret key → Dashboard (stats + charts)
→ Drivers list → Review documents → Approve/Reject
→ Customer management → Booking history & details
```

---

## 🛠️ API Reference

### Auth Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/send-otp` | Send OTP to phone |
| POST | `/api/auth/verify-otp` | Customer OTP verify + login |
| POST | `/api/auth/driver-verify-otp` | Driver OTP verify + login |
| POST | `/api/auth/admin-login` | Admin login with secret key |

### Customer Endpoints (Bearer Token)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/customer/create-booking` | Create transport request |
| GET | `/api/customer/active-booking` | Get active booking |
| GET | `/api/customer/booking/:id` | Get booking details |
| POST | `/api/customer/cancel-booking` | Cancel booking |
| POST | `/api/customer/rate-booking` | Rate completed trip |
| GET | `/api/customer/booking-history` | Trip history |
| GET | `/api/customer/nearby-drivers` | List nearby drivers |
| PUT | `/api/customer/update-location` | Update GPS location |

### Driver Endpoints (Bearer Token)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/driver/register` | Register (multipart form) |
| GET | `/api/driver/profile` | Driver profile |
| PUT | `/api/driver/toggle-online` | Go online/offline |
| PUT | `/api/driver/update-location` | Update GPS location |
| POST | `/api/driver/respond-booking` | Accept or reject |
| POST | `/api/driver/start-trip` | Start the trip |
| POST | `/api/driver/complete-trip` | Complete the trip |
| GET | `/api/driver/trip-history` | Trip history |

### Admin Endpoints (Bearer Token + Admin Role)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/admin/dashboard` | Stats + charts |
| GET | `/api/admin/drivers` | List drivers (filterable) |
| GET | `/api/admin/driver/:id` | Driver details |
| PUT | `/api/admin/driver/:id/approve` | Approve driver |
| PUT | `/api/admin/driver/:id/reject` | Reject with reason |
| GET | `/api/admin/users` | List customers |
| PUT | `/api/admin/user/:id/toggle` | Block/unblock user |
| GET | `/api/admin/bookings` | All bookings |

---

## 🔌 Real-Time Socket Events

### Client → Server
| Event | Payload | Description |
|-------|---------|-------------|
| `join_booking` | `bookingId` | Join booking room |
| `driver_location` | `{lat, lng, bookingId}` | Driver location update |
| `customer_location` | `{lat, lng, bookingId}` | Customer location update |

### Server → Client
| Event | Description |
|-------|-------------|
| `new_booking_request` | New trip request for driver |
| `booking_accepted` | Customer: driver found |
| `driver_location_update` | Customer: driver moving |
| `trip_started` | Both: trip began |
| `trip_completed` | Both: trip done |
| `booking_cancelled` | Both: booking cancelled |

---

## 🚛 Vehicle Types & Fare Structure

| Type | Icon | Base Fare | Per KM | Use Case |
|------|------|-----------|--------|----------|
| Bike | 🏍️ | ₹20 | ₹8 | Small packages |
| Auto | 🛺 | ₹30 | ₹12 | Medium goods |
| Mini Truck | 🚐 | ₹80 | ₹20 | Furniture, appliances |
| Tempo | 🚚 | ₹100 | ₹30 | Office shifting |
| Truck | 🚛 | ₹200 | ₹50 | Heavy goods |
| Pickup | 🛻 | ₹120 | ₹35 | Flat goods, bikes |

> Fare negotiation happens via phone call (no in-app payment).

---

## 🗄️ Database Schema

### MongoDB Collections
- **users** — Customers, drivers, admins with location index
- **drivers** — Driver profiles, documents, approval status
- **bookings** — All trip records with geospatial pickup/dropoff
- **otps** — OTP records with TTL auto-expiry (5 min)

### Geospatial Queries
The app uses MongoDB's `$near` operator for:
- Finding drivers within 5km of pickup
- Expanding search radius automatically if no drivers found

---

## 🏗️ Architecture

```
Android App
    │
    ├─ Retrofit2 (REST API) ──────────────────┐
    └─ Socket.IO client (real-time) ──────────┤
                                              ▼
                                    Node.js + Express
                                    + Socket.IO Server
                                          │
                              ┌───────────┤
                              ▼           ▼
                           MongoDB    Firebase Admin
                         (data store) (push notifications)

Admin Panel (React SPA)
    └─ Axios REST ────────────► Same Express API
```

---

## 🔐 Security Features
- JWT authentication (7-day expiry)
- Rate limiting (100 req/15min per IP)
- Helmet.js security headers
- OTP expiry (5 minutes, 3 attempt limit)
- Role-based access control (customer/driver/admin)
- File upload validation (type + size)
- Input validation with express-validator

---

## 📱 Adding to Production

### Backend Deployment (Render/Railway/EC2)
```bash
# Set NODE_ENV=production in .env
# Update BASE_URL in Android build.gradle
# Set OTP_DEV_MODE=false
# Configure real Twilio credentials
# Configure Firebase credentials
npm start
```

### Android Release Build
```bash
# In Android Studio:
# Build → Generate Signed Bundle/APK
# Follow keystore creation wizard
# Upload to Play Store
```

### Admin Panel Deployment (Vercel/Netlify)
```bash
cd admin-panel
REACT_APP_API_URL=https://your-backend.com/api npm run build
# Upload build/ folder to hosting
```

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| "Network error" in app | Check device IP in build.gradle |
| OTP not received | Enable OTP_DEV_MODE=true, check console |
| Map not loading | Add Google Maps API key |
| Push notifications not working | Add google-services.json |
| MongoDB connection failed | Check MONGODB_URI in .env |
| Driver location not updating | Grant location permission |
| Socket not connecting | Check SOCKET_URL matches backend |

---

## 📦 Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| Android | Kotlin, Jetpack, Hilt DI, Retrofit2, Socket.IO |
| Maps | Google Maps SDK, FusedLocationProvider |
| Backend | Node.js, Express.js, Socket.IO |
| Database | MongoDB + Mongoose (geospatial) |
| Auth | JWT + OTP via Twilio |
| Push Notifications | Firebase Cloud Messaging |
| Admin Panel | React.js, Chart.js, React Router |
| File Uploads | Multer (local disk, move to S3 for production) |

---

*Built with ❤️ — Movezy v1.0.0*
# movezy
# movezy
