plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.talentbridge.offline_navigator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.talentbridge.offline_navigator"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // valhalla-mobile declares minSdk 26 (0.1.0 and 0.3.0 both), so the app
        // floor must be >= 26 or the manifest merge fails. Keep Flutter's value
        // if it's higher.
        minSdk = maxOf(flutter.minSdkVersion, 26)
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 0.3.0 (Nov 2025) is the newest release that keeps the public `ValhallaActor`
    // raw-string API we use; 0.3.1+ made it `internal`. Bumped from the original
    // 0.1.0 (Oct 2024) to pull ~13 months of newer native builds — far more likely
    // to load on a modern device (NDK / 16 KB memory-page support) and a Valhalla
    // engine version aligned with the tiles we build from `valhalla/valhalla:latest`.
    implementation("io.github.rallista:valhalla-mobile:0.3.0")
}
