import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

class PhoneAuthStartResult {
  final bool requiresCode;
  final UserCredential? credential;

  const PhoneAuthStartResult._({
    required this.requiresCode,
    this.credential,
  });

  const PhoneAuthStartResult.codeSent() : this._(requiresCode: true);

  const PhoneAuthStartResult.completed(UserCredential credential)
      : this._(requiresCode: false, credential: credential);
}

class PhoneAuthService {
  PhoneAuthService._();

  static final instance = PhoneAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  int? _forceResendingToken;

  Future<PhoneAuthStartResult> sendOtp(String phone) async {
    final completer = Completer<PhoneAuthStartResult>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      forceResendingToken: _forceResendingToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        if (completer.isCompleted) return;
        final userCredential = await _auth.signInWithCredential(credential);
        completer.complete(
          PhoneAuthStartResult.completed(userCredential),
        );
      },
      verificationFailed: (FirebaseAuthException e) {
        if (completer.isCompleted) return;
        completer.completeError(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _forceResendingToken = resendToken;
        if (completer.isCompleted) return;
        completer.complete(const PhoneAuthStartResult.codeSent());
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );

    return completer.future;
  }

  Future<UserCredential> verifyOtp(String smsCode) async {
    final verificationId = _verificationId;
    if (verificationId == null) {
      throw FirebaseAuthException(
        code: 'missing-verification-id',
        message: 'Please request a new OTP and try again.',
      );
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }
}
