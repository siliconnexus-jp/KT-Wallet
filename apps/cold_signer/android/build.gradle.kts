import java.util.Properties

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use(::load)
}

// Local monorepo builds may share the already-ignored KT Wallet credentials;
// CI and standalone builds should provide the same values as Gradle properties.
val sharedWalletProperties = Properties().apply {
    val file = rootProject.file("../../kt_wallet/android/local.properties")
    if (file.exists()) file.inputStream().use(::load)
}

val useWalletCore = (
    providers.gradleProperty("walletCore").orNull
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

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}


tasks.register("verifyReleaseRuntimeDependencies") {
    group = "verification"
    description = "Resolves the locked, checksum-verified Android release runtime graph."
    dependsOn(":app:checkReleaseDuplicateClasses", ":app:mergeReleaseNativeLibs")
}
