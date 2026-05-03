import 'package:flutter/material.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/datasources/api_service.dart';

/// Outcome after a successful API cancel (fee is informational until payments are wired).
class CustomerCancelBookingResult {
  final int cancellationFeeInr;

  const CustomerCancelBookingResult({required this.cancellationFeeInr});
}

Future<bool> _confirmCancelDialog(BuildContext context, String title, String body) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
      content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('No'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Yes', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ),
  );
  return res == true;
}

/// Quote → confirm → cancel. Shows snackbars; returns result on success, null otherwise.
Future<CustomerCancelBookingResult?> runCustomerCancelBookingFlow({
  required BuildContext context,
  required ApiService api,
  required String bookingMongoId,
}) async {
  Map<String, dynamic>? quote;
  try {
    quote = await api.getBookingCancelQuote(bookingMongoId);
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Could not load cancel details. Try again.', error: true);
    }
    return null;
  }
  if (quote['canCancel'] != true) {
    if (context.mounted) {
      showSnack(context, '${quote['reason'] ?? 'Cannot cancel'}', error: true);
    }
    return null;
  }
  final fee = (quote['cancellationFeeInr'] as num?)?.round() ?? 0;
  final status = '${quote['status'] ?? ''}';
  final inTrip = status == 'in_progress';
  final body = fee > 0
      ? 'A cancellation fee of ₹$fee may apply for this trip phase${inTrip ? ' (trip in progress)' : ''}. '
          'Payment may be collected offline or adjusted per Movezy policy.'
      : 'You can cancel this booking at no charge.';
  final ok = await _confirmCancelDialog(context, 'Cancel this booking?', body);
  if (!ok || !context.mounted) return null;
  try {
    final res = await api.cancelBooking(bookingMongoId);
    final charged = (res['cancellationFeeInr'] as num?)?.round() ?? fee;
    if (context.mounted) {
      showSnack(
        context,
        charged > 0
            ? 'Booking cancelled. Applicable fee: ₹$charged.'
            : 'Booking cancelled',
      );
    }
    return CustomerCancelBookingResult(cancellationFeeInr: charged);
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Cancel failed', error: true);
    }
    return null;
  }
}
