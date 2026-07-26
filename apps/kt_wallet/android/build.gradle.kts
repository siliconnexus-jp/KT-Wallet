import java.util.Properties

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use(::load)
}

val useWalletCore =
    (localProperties.getProperty("walletCore") ?: "false").toBoolean()

allprojects {
    repositories {
        google()
        mavenCentral()
        if (useWalletCore) {
            maven {
                url = uri("https://maven.pkg.github.com/trustwallet/wallet-core")
                credentials {
                    username = localProperties.getProperty("gpr.user")
                    password = localProperties.getProperty("gpr.token")
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
