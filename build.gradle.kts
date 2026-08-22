import java.util.Properties

plugins {
    base
}

group = "com.knoxsurvivors"
version = "0.0.1-dev"

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.isFile) {
        file.inputStream().use(::load)
    }
}

val workshopRoot = providers.gradleProperty("workshopRoot")
    .orElse(localProperties.getProperty("workshopRoot") ?: "")

val workshopModFolder = providers.gradleProperty("workshopModFolder")
    .orElse(localProperties.getProperty("workshopModFolder") ?: "KnoxSurvivorsRebuild")

tasks.register<Copy>("deployDev") {
    group = "knox survivors"
    description = "Builds and copies the development mod into the configured PZ Workshop directory."
    dependsOn(":java:jar")

    doFirst {
        require(workshopRoot.get().isNotBlank()) {
            "Set workshopRoot in local.properties before deploying."
        }
    }

    into(workshopRoot.zip(workshopModFolder) { root, folder -> file(root).resolve(folder) })
    from(layout.projectDirectory.dir("mod"))
    from(project(":java").layout.buildDirectory.dir("libs")) {
        include("knox-agent-*.jar")
        into("java/build/libs")
    }
}
