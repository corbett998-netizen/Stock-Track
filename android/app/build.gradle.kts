plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Core: processes android/app/google-services.json for project
    // easy-stock-track (Brandon's own). Must be applied after the Android plugin.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.stocktrack.stock_track"
    compileSdk = flutter.compileSdkVersion
    // firebase_core 4.x expects NDK 27; pin it (installed) to clear the mismatch
    // warning. NDK versions are backward compatible.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required by flutter_local_notifications (harness push heads-up): the plugin uses
        // java.time APIs that must be desugared to run on minSdk 23. Without this the
        // release build fails. Paired with the desugar_jdk_libs dependency below.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Brandon's Stock-Track application id (his own org, not Blueprint Fitness, not io.flutter).
        applicationId = "com.stocktrack.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase Core (firebase_core 4.x) requires minSdk 23 (Android 6.0);
        // raised from Flutter's default 21 for the Firebase wiring.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core-library desugaring runtime for flutter_local_notifications (harness push
    // heads-up). Must be present when isCoreLibraryDesugaringEnabled = true above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
