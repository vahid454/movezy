import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:movezy/core/constants/app_constants.dart';

typedef JsonCb = void Function(Map<String, dynamic> data);

class SocketService {
  SocketService._();
  static final instance = SocketService._();

  sio.Socket? _socket;

  bool get connected => _socket?.connected ?? false;

  void connect(String token) {
    if (connected) return;
    _socket = sio.io(
      AppConstants.socketUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionAttempts(8)
          .setReconnectionDelay(1200)
          .disableAutoConnect()
          .build(),
    );
    _socket!.connect();
    _socket!.onConnect((_) => print('[Socket] connected'));
    _socket!.onDisconnect((_) => print('[Socket] disconnected'));
    _socket!.onConnectError((e) => print('[Socket] error: $e'));
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void joinBooking(String id) => _socket?.emit('join_booking', id);

  void emitDriverLoc(double lat, double lng, {String? bookingId}) {
    _socket?.emit('driver_location', {
      'latitude': lat,
      'longitude': lng,
      if (bookingId != null) 'bookingId': bookingId,
    });
  }

  void emitCustomerLoc(double lat, double lng, {String? bookingId}) {
    _socket?.emit('customer_location', {
      'latitude': lat,
      'longitude': lng,
      if (bookingId != null) 'bookingId': bookingId,
    });
  }

  void on(String event, JsonCb cb) {
    _socket?.on(event, (raw) {
      if (raw is Map<String, dynamic>) {
        cb(raw);
      } else if (raw is Map) {
        cb(Map<String, dynamic>.from(raw));
      }
    });
  }

  void off(String event) => _socket?.off(event);

  void offAll() {
    for (final e in [
      'new_booking_request',
      'booking_accepted',
      'driver_location_update',
      'customer_location_update',
      'trip_started',
      'trip_completed',
      'booking_cancelled',
    ]) {
      _socket?.off(e);
    }
  }
}
