# Nexa SDK - Keep all classes accessed via JNI reflection
# The native library accesses these classes by name and field names
-keep class com.nexa.sdk.** { *; }
-keepclassmembers class com.nexa.sdk.** { *; }

# Keep specifically the bean classes that JNI accesses
-keep class com.nexa.sdk.bean.** { *; }
-keepclassmembers class com.nexa.sdk.bean.** {
    <fields>;
    <methods>;
}

# Keep JNI classes
-keep class com.nexa.sdk.jni.** { *; }
-keepclassmembers class com.nexa.sdk.jni.** { *; }

# Don't warn about Nexa SDK
-dontwarn com.nexa.sdk.**

# Keep native method names
-keepclasseswithmembernames class * {
    native <methods>;
}
