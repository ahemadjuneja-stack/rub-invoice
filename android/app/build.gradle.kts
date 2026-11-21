import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// GOAL 3 (v0.4.1) - SECRETS OUT OF THE REPO.
//
// The release keystore is NO LONGER committed. Signing values come from
// android/key.properties (gitignored), which is:
//   * written locally by the developer (keep ruby-invoice.keystore on
//     disk, never git add it), and
//   * restored inside CI by the workflow from GitHub Actions Secrets
//     (ANDROID_KEYSTORE_BASE64 / _PASSWORD / _ALIAS / _KEY_PASSWORD)
//     - see docs/SECURITY.md.
// If key.properties is missing (fresh clone without secrets), the
// release build falls back to the plain DEBUG key and prints a LOUD
// warning: such an APK installs fresh but CANNOT update an existing
// signed install - do not distribute it.
val keystoreProps = Properties()
val keyPropsFile = rootProject.file("key.properties")
if (keyPropsFile.exists()) {
    keyPropsFile.inputStream().use { keystoreProps.load(it) }
}
val ksPath = keystoreProps.getProperty("storeFile")
val ksStorePass = keystoreProps.getProperty("storePassword")
val ksKeyAlias = keystoreProps.getProperty("keyAlias")
val ksKeyPass = keystoreProps.getProperty("keyPassword")
val ksFile = ksPath?.let { file(it) }
val hasReleaseKey =
    ksFile != null && ksFile.exists() &&
    ksStorePass != null && ksKeyAlias != null && ksKeyPass != null

android {
    namespace = "com.rubyinvoice.ruby_invoice"
    // Pinned explicitly (matches flutter.compileSdkVersion of the pinned
    // CI Flutter SDK): protects the AAR metadata checks from drift when
    // a plugin resolves with a dynamic compileSdk.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rubyinvoice.ruby_invoice"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Values are resolved at the top of this file (imports + key.properties).
    signingConfigs {
        if (hasReleaseKey) {
            create("rubyRelease") {
                storeFile = ksFile!!
                storePassword = ksStorePass
                keyAlias = ksKeyAlias
                keyPassword = ksKeyPass
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("rubyRelease")
            } else {
                signingConfig = signingConfigs.getByName("debug")
                println(
                    "WARNING: android/key.properties (release keystore) is missing - " +
                    "this APK is DEBUG-SIGNED and cannot update existing installs. " +
                    "Restore key.properties locally or set the ANDROID_* CI secrets."
                )
            }
            // SECURITY HARDENING (v0.2.21): R8 code shrinking + resource
            // shrinking + obfuscation. The Java/Kotlin glue (Firebase
            // auth, Google Sign-In, sqflite bridge) is stripped and
            // renamed, so the APK resists trivial reverse engineering.
            // Flutter's Dart code lives in libapp.so (AOT snapshot) and
            // is not affected by R8; the keep-rules below preserve only
            // what reflection (Firebase/Play Services) needs.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
