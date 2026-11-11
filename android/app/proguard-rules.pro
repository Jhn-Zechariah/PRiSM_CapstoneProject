# App-specific R8 rules. Flutter's own rules are added automatically.

# Android Studio only indexes this module, so it can't see classes that come
# from Flutter plugins (com.dexterous.*) or their libraries (Gson) and marks
# them as "Unresolved class name". R8 does see them at build time.
#noinspection ShrinkerUnresolvedReference

# flutter_local_notifications 17.x ships no consumer rules and serialises
# notification details with Gson. Without these rules, R8 strips generic type
# info and scheduled/stored notifications crash with "Missing type parameter".
-keep class com.dexterous.** { *; }

# Gson (from google/gson examples/android-proguard-example)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod,InnerClasses
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Flutter deferred components reference Play Core classes the app doesn't ship.
-dontwarn com.google.android.play.core.**
