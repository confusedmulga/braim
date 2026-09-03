# R8/ProGuard keep rules for release (minified) builds.

# --- flutter_local_notifications -------------------------------------------
# On boot the plugin reloads scheduled notifications with Gson, whose TypeToken
# needs the generic Signature attribute that R8 strips by default. Without
# these, a minified release build crashes on every reboot with
# "java.lang.RuntimeException: Missing type parameter." from
# ScheduledNotificationBootReceiver.onReceive.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod

# --- Gson (used by flutter_local_notifications to (de)serialize schedules) --
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
