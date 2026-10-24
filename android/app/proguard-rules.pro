# shared_preferences_android calls the Kotlin coroutine API through JNI. R8
# renames Continuation in release builds, which makes the JNI signature lookup
# fail with NoSuchMethodError before Flutter can draw its first frame.
-keep class kotlin.coroutines.Continuation { *; }
-keep interface kotlin.coroutines.Continuation { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
