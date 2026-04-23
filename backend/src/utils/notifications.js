let firebaseAdmin = null;

const initFirebase = () => {
  if (firebaseAdmin) return firebaseAdmin;
  try {
    const admin = require('firebase-admin');
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL
        })
      });
    }
    firebaseAdmin = admin;
    return admin;
  } catch (err) {
    console.warn('Firebase not configured:', err.message);
    return null;
  }
};

const sendPushNotification = async (fcmToken, title, body, data = {}) => {
  if (!fcmToken) return;

  const admin = initFirebase();
  if (!admin) {
    console.log(`[DEV] Push: ${title} - ${body} to ${fcmToken.substring(0, 10)}...`);
    return;
  }

  try {
    const message = {
      token: fcmToken,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: { priority: 'high', notification: { sound: 'default' } },
      apns: { payload: { aps: { sound: 'default' } } }
    };
    const response = await admin.messaging().send(message);
    console.log('Push sent:', response);
    return response;
  } catch (err) {
    console.error('Push notification error:', err.message);
  }
};

const sendMulticastNotification = async (fcmTokens, title, body, data = {}) => {
  const validTokens = fcmTokens.filter(Boolean);
  if (!validTokens.length) return;

  const admin = initFirebase();
  if (!admin) {
    console.log(`[DEV] Multicast Push: ${title} to ${validTokens.length} devices`);
    return;
  }

  try {
    const message = {
      tokens: validTokens,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: { priority: 'high' }
    };
    return await admin.messaging().sendEachForMulticast(message);
  } catch (err) {
    console.error('Multicast push error:', err.message);
  }
};

module.exports = { sendPushNotification, sendMulticastNotification };
