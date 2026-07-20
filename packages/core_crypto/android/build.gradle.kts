group = "com.ktwallet.core_crypto"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

// Trust Wallet Core's Android artifact is published only to GitHub Packages
// (auth required); it is NOT on Maven Central. To keep the repo building on
// Android out of the box, wallet-core is OPT-IN via `-PwalletCore=true`
// (or walletCore=true in the app's android/gradle.properties). When off (the
// default), an API-identical fail-closed stub bridge is compiled instead so the
// full UI runs, but no key/address/signature can be produced on Android.
val useWalletCore = (project.findProperty("walletCore")?.toString() ?: "false")
    .toBoolean()

android {
    namespace = "com.ktwallet.core_crypto"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            // Swap in the real wallet-core bridge or the fail-closed stub.
            java.srcDir(if (useWalletCore) "src/walletcore/kotlin" else "src/stub/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Trust Wallet Core: audited crypto (mnemonic, derivation, signing).
    // Opt-in — see `useWalletCore` above. Requires the GitHub Packages Maven
    // repo with credentials:
    //   maven {
    //     url = uri("https://maven.pkg.github.com/trustwallet/wallet-core")
    //     credentials { username = <gh-user>; password = <gh-token:read:packages> }
    //   }
    if (useWalletCore) {
        implementation("com.trustwallet:wallet-core:4.7.0")
    }
    // Biometric prompt for the AuthGate.
    implementation("androidx.biometric:biometric:1.1.0")
    // Argon2id KDF for the Cold Signer second encryption layer.
    implementation("com.lambdapioneer.argon2kt:argon2kt:1.5.0")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.0")
}
