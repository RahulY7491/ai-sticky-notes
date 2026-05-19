# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Core — referenced by Flutter's deferred component manager
# but not bundled; safe to suppress.
-dontwarn com.google.android.play.core.**

# Google Play Billing
-keep class com.android.vending.billing.** { *; }

# Flutter Secure Storage (Android Keystore)
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# In-App Purchase plugin
-keep class com.flutter.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**

# Prevent stripping of Hive type adapters
-keep class ** extends com.google.protobuf.GeneratedMessageLite { *; }

# Remove Log statements in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}
