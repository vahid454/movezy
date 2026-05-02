import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movezy/core/constants/app_constants.dart';

/// Cached map marker bitmaps (vehicle emoji on a pin-style circle).
class VehicleMapIcons {
  VehicleMapIcons._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Default full-size marker (booking preview, driver app).
  static const double kLogicalSideDefault = 112;

  /// Smaller markers on the customer home map (less visual clutter).
  static const double kLogicalSideCompact = 72;

  static String _emojiFor(String vehicleType) {
    return vehicleByType(vehicleType)?.emoji ?? '🚚';
  }

  static String _cacheKey(String vehicleType, double logicalSide) {
    final key = vehicleType.trim().isEmpty ? 'auto' : vehicleType.trim();
    return '$key@${logicalSide.toStringAsFixed(0)}';
  }

  /// Builds a square marker bitmap; safe to call from UI isolate after binding.
  /// [logicalSide] is logical pixels before DPR (e.g. [kLogicalSideCompact] for a smaller pin).
  static Future<BitmapDescriptor> forVehicleType(
    String vehicleType, {
    double logicalSide = kLogicalSideDefault,
  }) async {
    final sideLogical = logicalSide.clamp(48.0, 160.0);
    final cacheKey = _cacheKey(vehicleType, sideLogical);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final views = ui.PlatformDispatcher.instance.views;
    final dpr = views.isEmpty ? 2.0 : views.first.devicePixelRatio;
    final side = (sideLogical * dpr).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(side / 2, side / 2);
    final scale = sideLogical / kLogicalSideDefault;
    final radius = side * 0.38;

    final shadow = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter =
          MaskFilter.blur(BlurStyle.normal, (4 * scale).clamp(2.0, 6.0) * dpr);
    canvas.drawCircle(center.translate(0, 2 * dpr), radius + 2, shadow);

    final fill = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(center, radius, fill);

    final ring = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (3 * scale).clamp(1.5, 3.5) * dpr;
    canvas.drawCircle(center, radius, ring);

    final emojiKey = vehicleType.trim().isEmpty ? 'auto' : vehicleType.trim();
    final emoji = _emojiFor(emojiKey);
    final emojiPx = (44 * dpr * scale).clamp(18 * dpr, 52 * dpr);
    final tp = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(
          fontSize: emojiPx,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: side.toDouble());
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    final picture = recorder.endRecording();
    final image = await picture.toImage(side, side);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    }
    final Uint8List png = bd.buffer.asUint8List();
    final icon = BitmapDescriptor.bytes(png, imagePixelRatio: dpr);
    _cache[cacheKey] = icon;
    return icon;
  }

  static Future<void> preloadAll() async {
    for (final v in kVehicles) {
      await forVehicleType(v.type);
      await forVehicleType(v.type, logicalSide: kLogicalSideCompact);
    }
  }
}
