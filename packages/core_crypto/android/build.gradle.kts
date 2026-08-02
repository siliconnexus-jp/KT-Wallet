import java.util.Properties

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

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use(::load)
}

// Both apps live in one workspace. Reuse the main app's ignored local
// credentials when the independently buildable Cold Signer has no copy;
// explicit Gradle properties always win and remain the CI/release contract.
val sharedWalletProperties = Properties().apply {
    val file = rootProject.file("../../kt_wallet/android/local.properties")
    if (file.exists()) file.inputStream().use(::load)
}

val useWalletCore = (
    project.findProperty("walletCore")?.toString()
        ?: localProperties.getProperty("walletCore")
        ?: sharedWalletProperties.getProperty("walletCore")
        ?: "false"
).toBoolean()
val walletCoreUser = providers.gradleProperty("gpr.user").orNull
    ?: localProperties.getProperty("gpr.user")
    ?: sharedWalletProperties.getProperty("gpr.user")
val walletCoreToken = providers.gradleProperty("gpr.token").orNull
    ?: localProperties.getProperty("gpr.token")
    ?: sharedWalletProperties.getProperty("gpr.token")
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseRequested && !useWalletCore) {
    throw GradleException(
        "Android release builds require Trust Wallet Core; set walletCore=true " +
            "and configure read-only GitHub Packages credentials.",
    )
}

if (useWalletCore && (walletCoreUser.isNullOrBlank() || walletCoreToken.isNullOrBlank())) {
    throw GradleException(
        "walletCore=true requires gpr.user and a read-only gpr.token.",
    )
}

allprojects {
    repositories {
        google()
        mavenCentral()
        if (useWalletCore) {
            maven {
                url = uri("https://maven.pkg.github.com/trustwallet/wallet-core")
                credentials {
                    username = walletCoreUser
                    password = walletCoreToken
                }
            }
        }
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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
        // Wallet Core 4.7.0 declares protobuf-javalite 3.22.3. Keep the
        // generated 3.x messages on the supported 3.25 maintenance line while
        // removing GHSA-735f-pc8j-v9w8 and the later footmitten exposure.
        // Protobuf guarantees older Java gencode works on a newer runtime in
        // the same major version; this is also exercised by the native bridge
        // and release builds below.
        implementation("com.google.protobuf:protobuf-javalite:3.25.8")
    }
    // Biometric prompt for the AuthGate.
    implementation("androidx.biometric:biometric:1.1.0")
    // Argon2id KDF for the Cold Signer second encryption layer.
    implementation("com.lambdapioneer.argon2kt:argon2kt:1.5.0")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}
