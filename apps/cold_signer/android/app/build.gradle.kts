plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material comes from the environment only — never the repo.
// The signer holds the seed, so shipping it under Android's shared debug key
// (whose password is the public string "android") would let anyone sign a
// look-alike "update". Same contract as kt_wallet; see BUILDING.md.
val releaseStoreFile = System.getenv("KT_SIGNER_RELEASE_STORE_FILE")
val releaseStorePassword = System.getenv("KT_SIGNER_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("KT_SIGNER_RELEASE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("KT_SIGNER_RELEASE_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "cc.siliconnexus.ktwallet.coldsigner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cc.siliconnexus.ktwallet.coldsigner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Fail closed: without the four env vars there is no signing config,
            // so the build produces an unsigned artifact instead of one signed
            // with the shared debug key.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                null
            }
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
