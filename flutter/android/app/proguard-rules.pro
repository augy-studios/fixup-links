# What R8 mustn't rename or remove in a release build. Libraries bring their own rules; these are
# for what this app looks up by name.

# The bridge (bridge/Bridge.java) makes each plugin from its class and reads @AppPlugin off it, then
# finds its methods by their annotations and their names: the Dart side's Native.call names a
# @PluginMethod, and requestPermissionForAlias and startActivityForResult name a callback.
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault
-keep @interface org.uwuapps.fixup.bridge.* { *; }
-keep class * extends org.uwuapps.fixup.bridge.Plugin {
    <init>();
}
-keepclassmembers class org.uwuapps.fixup.bridge.Plugin {
    @org.uwuapps.fixup.bridge.PluginMethod <methods>;
    @org.uwuapps.fixup.bridge.PermissionCallback <methods>;
    @org.uwuapps.fixup.bridge.ActivityCallback <methods>;
}
-keepclassmembers class * extends org.uwuapps.fixup.bridge.Plugin {
    @org.uwuapps.fixup.bridge.PluginMethod <methods>;
    @org.uwuapps.fixup.bridge.PermissionCallback <methods>;
    @org.uwuapps.fixup.bridge.ActivityCallback <methods>;
}

# flutter_webrtc's Java side is reached from its native library by name (JNI).
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }

# Flutter's embedding refers to Play's deferred components, which this app doesn't use.
-dontwarn com.google.android.play.core.**

# Readable line numbers in a crash, once its names are put back with the build's mapping.txt: Play
# has it from the bundle, and build-apk.ps1 keeps the APK's in release/<version>/.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
