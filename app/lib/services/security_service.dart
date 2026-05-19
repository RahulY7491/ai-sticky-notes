import 'package:flutter/foundation.dart';

/// Lightweight debug-only logger used throughout the app.
///
/// Previously this file held HMAC entitlement logic for in-app purchase
/// verification. Payments have been removed from the app, so only the
/// logging helper remains.
class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  static void log(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }
}
