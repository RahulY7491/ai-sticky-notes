import 'package:flutter/material.dart';

/// All AI actions are free — no paywall, no daily limit, no Pro gating.
///
/// This class is kept as a thin compatibility shim so existing call sites
/// (`UsageGate.instance.guardAiAction(context)`) continue to compile without
/// changes.
class UsageGate {
  UsageGate._();
  static final UsageGate instance = UsageGate._();

  Future<bool> guardAiAction(BuildContext context) async => true;
}
