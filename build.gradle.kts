import java.security.MessageDigest
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
    .orElse(localProperties.getProperty("workshopModFolder") ?: "KnoxSurvivors")

val localModsRoot = providers.gradleProperty("localModsRoot")
    .orElse(localProperties.getProperty("localModsRoot") ?: "")

val writeAgentChecksum by tasks.registering {
    group = "knox survivors"
    description = "Writes the Workshop Java-agent SHA-256 sidecar."
    dependsOn(":java:jar")

    val agentJar = project(":java").layout.buildDirectory.file(
        "libs/knox-agent-${project.version}.jar"
    )
    val checksumFile = project(":java").layout.buildDirectory.file(
        "libs/knox-agent-${project.version}.jar.sha256"
    )
    inputs.file(agentJar)
    outputs.file(checksumFile)

    doLast {
        val jarFile = agentJar.get().asFile
        val digest = MessageDigest.getInstance("SHA-256")
        jarFile.inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val hash = digest.digest().joinToString("") { byte -> "%02x".format(byte) }
        checksumFile.get().asFile.writeText("$hash  ${jarFile.name}\n")
    }
}

tasks.register<Copy>("deployLocal") {
    group = "knox survivors"
    description = "Copies the development mod into the local Project Zomboid mods directory."
    dependsOn(":java:jar")

    doFirst {
        require(localModsRoot.get().isNotBlank()) {
            "Set localModsRoot in local.properties before deploying."
        }
    }

    into(localModsRoot.map { file(it).resolve("KnoxSurvivors") })
    from(layout.projectDirectory.dir("mod"))
}

tasks.register<Sync>("stageWorkshop") {
    group = "knox survivors"
    description = "Builds the Steam Workshop staging layout without publishing it."
    dependsOn(writeAgentChecksum)

    doFirst {
        require(workshopRoot.get().isNotBlank()) {
            "Set workshopRoot in local.properties before staging."
        }
        require(workshopModFolder.get().matches(Regex("[A-Za-z0-9][A-Za-z0-9._ -]*"))) {
            "workshopModFolder must be a single folder name, not a path."
        }
    }

    // Synchronize only the generated mod payload, never Workshop metadata or previews.
    into(workshopRoot.zip(workshopModFolder) { root, folder ->
        file(root).resolve(folder).resolve("Contents/mods/KnoxSurvivors")
    })
    from(layout.projectDirectory.dir("mod"))
    from(project(":java").layout.buildDirectory.dir("libs")) {
        include("knox-agent-${project.version}.jar", "knox-agent-${project.version}.jar.sha256")
        // Steam uploads Contents, not its parent Workshop staging folder.
        into("java")
    }
}

tasks.register("deployDev") {
    group = "knox survivors"
    description = "Builds and deploys both the local test mod and Workshop staging package."
    dependsOn("deployLocal", "stageWorkshop")
}

tasks.register("prepareWorkshopUpload") {
    group = "knox survivors"
    description = "Stages the mod and prepares the existing Workshop item's preview and description; does not publish."
    dependsOn("stageWorkshop")
    doLast {
        val root = file(workshopRoot.get()).resolve(workshopModFolder.get())
        val description = file("workshop/description.bbcode").readLines(Charsets.UTF_8)
        val metadata = listOf(
            "version=1", "id=3749727604",
            "title=[42.20.3] Knox Survivors - Early Rebuild (Launcher Required)"
        ) + description.map { "description=$it" } + listOf("tags=Build 42", "visibility=public")
        root.resolve("workshop.txt").writeText(metadata.joinToString("\n", postfix = "\n"), Charsets.UTF_8)
        file("mod/poster.png").copyTo(root.resolve("preview.png"), overwrite = true)
    }
}
