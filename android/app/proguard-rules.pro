# Prevent R8 from stripping away the NeuroSDK Flutter implementation
-keep class com.neurosdk2.flutter_impl.** { *; }
-keep class com.neurosdk2.neurosdk2.** { *; }

# Keep all NeuroSDK library classes
-keep class com.neurosdk2.** { *; }

# Also keep the standard Flutter and Plugin classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Don't warn about missing dependencies in the SDK
-dontwarn com.neurosdk2.**
