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
        applicationId = "cc.siliconnexus.ktwallet.coldsigner"
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

dependencies {
    testImplementation("junit:junit:4.13.2")
}

// Lock the production APK graph, while artifact bytes (including build tools)
// are independently enforced by dependency verification metadata.
configurations.configureEach {
    if (name == "releaseRuntimeClasspath") {
        resolutionStrategy.activateDependencyLocking()
    }
}

dependencyLocking {
    // Kotlin 2.3 exposes this metadata-only compatibility module as a runtime
    // constraint but not as a standalone APK artifact.
    ignoredDependencies.add("org.jetbrains.kotlin:kotlin-stdlib-common")
}
