# =====================================================================
# Ruby Invoice - R8 / ProGuard keep rules (v0.2.21 security hardening)
#
# Goal: obfuscate/shrink everything EXCEPT what reflection needs.
# Flutter's own consumer rules (flutter.gradle plugin) and the Firebase
# Android SDK consumer rules are applied automatically; the rules below
# cover the pieces that have no consumer rules and would otherwise
# crash a minified release build.
# =====================================================================

# ---- Flutter standard keeps -----------------------------------------
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.embedding.** { *; }

# Parcelable creators / SERIALIZABLE are reflectively resolved
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ---- Firebase (Auth / Firestore / Storage / Core) --------------------
# Keep the Google Play Services + Firebase plumbing: reflection-heavy.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase Auth Google sign-in + Credentials API
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ---- cloud_firestore: gRPC + protobuf need their names ---------------
-keep class io.grpc.** { *; }
-dontwarn io.grpc.**
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Firestore's generated protobuf/graal hints
-keep class com.google.cloud.** { *; }
-dontwarn com.google.cloud.**
-keep class com.google.longrunning.** { *; }
-keep class com.google.type.** { *; }
-dontwarn com.google.longrunning.**
-dontwarn com.google.type.**

# ---- sqflite (androidx.sqlite bridge) --------------------------------
-keep class androidx.sqlite.** { *; }
-keep class com.tekartik.sqflite.** { *; }

# ---- plugins used by the app -----------------------------------------
-keep class com.google.android.gms.security.** { *; }   # provider installer
-keep class androidx.work.** { *; }                     # background workers
-dontwarn androidx.**

# ---- generic safety nets ---------------------------------------------
# Annotations are only metadata - drop them to shrink further
-dontkeepattributes RuntimeVisibleAnnotations,AnnotationDefault
# Keep source file + line numbers OFF (obfuscation), but keep the
# mapping file uploaded by CI for crash symbolication:
#   build/app/outputs/mapping/release/mapping.txt
-renamesourcefileattribute SourceFile
