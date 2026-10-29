plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val envStoreFile = System.getenv("ANDROID_KEYSTORE_PATH")
val envStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val envKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
val envKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
val hasEnvSigning =
    !envStoreFile.isNullOrBlank() &&
        !envStorePassword.isNullOrBlank() &&
        !envKeyAlias.isNullOrBlank() &&
        !envKeyPassword.isNullOrBlank()

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasPropertiesSigning = keystorePropertiesFile.exists()
val isCi = System.getenv("CI") == "true"

android {
    namespace = "com.tursinalabs.kelola"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tursinalabs.kelola"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter.
        // https://flutter.dev/to/review-gradle-config
        // You can force using the value of versionCode by specifying the
        // `-P force-version-code-ignoring-abi=true` flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasEnvSigning || hasPropertiesSigning) {
            create("release") {
                if (hasEnvSigning) {
                    keyAlias = envKeyAlias
                    keyPassword = envKeyPassword
                    storeFile = file(envStoreFile!!)
                    storePassword = envStorePassword
                } else {
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                    storePassword = keystoreProperties["storePassword"] as String
                }
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            ndk {
                debugSymbolLevel = "FULL"
            }
            // Prefer env (CI) → android/key.properties (local) → debug (local only).
            // Never silently debug-sign a CI release.
            signingConfig = when {
                hasEnvSigning || hasPropertiesSigning ->
                    signingConfigs.getByName("release")
                isCi ->
                    throw GradleException(
                        "CI release build requires ANDROID_KEYSTORE_* env vars " +
                            "or android/key.properties; refusing debug signing.",
                    )
                else -> signingConfigs.getByName("debug")
            }
            // AGP 9 R8 full mode. WorkManager 2.9 dies without these keeps.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
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

dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.work:work-runtime-ktx:2.11.1")
}
