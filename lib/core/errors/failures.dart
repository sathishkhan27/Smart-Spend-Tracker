import 'dart:async';
import 'dart:developer' as dev;

import 'package:firebase_auth/firebase_auth.dart';

/// A user-presentable failure. Repositories translate low-level exceptions
/// into [AppFailure] so the UI never has to understand Firebase/HTTP errors.
class AppFailure implements Exception {
  const AppFailure(this.message, {this.code, this.cause});
  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => 'AppFailure($code): $message';
}

abstract final class ErrorHandler {
  /// Converts any thrown object into an [AppFailure].
  static AppFailure map(Object error) {
    if (error is AppFailure) return error;
    if (error is FirebaseAuthException) {
      return AppFailure(_authMessage(error.code), code: error.code, cause: error);
    }
    if (error is FirebaseException) {
      final msg = switch (error.code) {
        'permission-denied' => 'You do not have access to this data.',
        'unavailable' => 'Service unavailable. Check your connection and try again.',
        'not-found' => 'The requested record was not found.',
        _ => error.message ?? 'Something went wrong.',
      };
      return AppFailure(msg, code: error.code, cause: error);
    }
    if (error is TimeoutException) {
      return AppFailure('The request timed out. Please retry.', code: 'timeout', cause: error);
    }
    return AppFailure('Something went wrong. Please try again.', cause: error);
  }

  static String _authMessage(String code) => switch (code) {
        'invalid-email' => 'Please enter a valid email address.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Incorrect email or password.',
        'email-already-in-use' => 'An account already exists for this email.',
        'weak-password' => 'Choose a stronger password (at least 8 characters).',
        'too-many-requests' => 'Too many attempts. Please wait and try again.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Authentication failed. Please try again.',
      };

  /// Secure logging: never pass raw SMS/email bodies or account numbers here.
  static void log(Object error, [StackTrace? stack, String context = '']) {
    dev.log('[$context] ${error.runtimeType}: ${map(error).message}', name: 'SmartSpend', error: error, stackTrace: stack);
  }
}
