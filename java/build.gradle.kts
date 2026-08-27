import java.util.Properties

plugins {
    java
}

group = "com.knoxsurvivors"
version = rootProject.version

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.isFile) {
        file.inputStream().use(::load)
    }
}
val pzHome = providers.gradleProperty("pzHome")
    .orElse(localProperties.getProperty("pzHome") ?: "")

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

dependencies {
    compileOnly(files(pzHome.map { file(it).resolve("projectzomboid.jar") }))
}

tasks.register("verifyGameJar") {
    group = "verification"
    description = "Checks that the configured Project Zomboid game jar is available."

    doLast {
        require(pzHome.get().isNotBlank()) {
            "Set pzHome in local.properties before building."
        }
        val gameJar = file(pzHome.get()).resolve("projectzomboid.jar")
        require(gameJar.isFile) {
            "Project Zomboid jar not found at ${gameJar.absolutePath}"
        }
    }
}

tasks.compileJava {
    dependsOn("verifyGameJar")
    options.encoding = "UTF-8"
    options.release = 17
}

tasks.jar {
    archiveBaseName = "knox-agent"
    manifest {
        attributes(
            "Premain-Class" to "com.knoxsurvivors.agent.KnoxAgent",
            "Agent-Class" to "com.knoxsurvivors.agent.KnoxAgent",
            "Can-Redefine-Classes" to "true",
            "Can-Retransform-Classes" to "true",
            "Implementation-Title" to "Knox Survivors Java Agent",
            "Implementation-Version" to project.version
        )
    }
}

val verifyCombatTransformer by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies the narrow melee callback patch against the configured game jar."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.agent.KnoxSwipeStateTransformerVerifier")
    doFirst {
        val gameJar = file(pzHome.get()).resolve("projectzomboid.jar")
        args(gameJar.absolutePath)
    }
}

val verifyZombieVisibilityTransformer by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies the Knox shell visibility adapter against the configured game jar."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.agent.KnoxZombieVisibilityTransformerVerifier")
    doFirst {
        val gameJar = file(pzHome.get()).resolve("projectzomboid.jar")
        args(gameJar.absolutePath)
    }
}

val verifyZombieVisibilityRuntime by tasks.registering(Exec::class) {
    group = "verification"
    description = "Defines the transformed IsoZombie class with Project Zomboid's Java runtime."
    dependsOn(tasks.testClasses)
    doFirst {
        val gameHome = file(pzHome.get())
        val gameJar = gameHome.resolve("projectzomboid.jar")
        val javaRuntime = gameHome.resolve("jre64/bin/java.exe")
        require(javaRuntime.isFile) {
            "Project Zomboid Java runtime not found at ${javaRuntime.absolutePath}"
        }
        val classpath = listOf(
            sourceSets.main.get().output.classesDirs.asPath,
            sourceSets.test.get().output.classesDirs.asPath,
            gameJar.absolutePath,
        ).joinToString(System.getProperty("path.separator"))
        commandLine(
            javaRuntime.absolutePath,
            "-Xverify:all",
            "-cp",
            classpath,
            "com.knoxsurvivors.agent.KnoxZombieVisibilityClassVerifier",
            gameJar.absolutePath,
        )
    }
}

val verifyIsoPlayerShellPolicy by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies that the generated NPC shell never claims local input ownership."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.engine.KnoxIsoPlayerShellPolicyVerifier")
}

tasks.check {
    dependsOn(
        verifyCombatTransformer,
        verifyZombieVisibilityTransformer,
        verifyZombieVisibilityRuntime,
        verifyIsoPlayerShellPolicy,
    )
}
