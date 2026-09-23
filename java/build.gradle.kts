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
val zombieBuddyJar = providers.gradleProperty("zombieBuddyJar")
    .orElse(localProperties.getProperty("zombieBuddyJar") ?: "")

fun resolvedZombieBuddyJar(): File {
    val configured = zombieBuddyJar.get().trim()
    if (configured.isNotEmpty()) return file(configured)
    return file(pzHome.get()).resolve("ZombieBuddy.jar")
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

dependencies {
    compileOnly(files(pzHome.map { file(it).resolve("projectzomboid.jar") }))
    // ZombieBuddy's released v2.3.2 Patch API is compile-only. At runtime the user-provided
    // ZombieBuddy installation owns this class; Knox does not bundle or replace ZombieBuddy.
    compileOnly(files(providers.provider { resolvedZombieBuddyJar() }))
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

tasks.register("verifyZombieBuddyApi") {
    group = "verification"
    description = "Checks that ZombieBuddy.jar is available for compile-only Patch API types."

    doLast {
        val jar = resolvedZombieBuddyJar()
        require(jar.isFile) {
            "ZombieBuddy.jar not found at ${jar.absolutePath}. Install ZombieBuddy next to Project Zomboid or set zombieBuddyJar in local.properties."
        }
    }
}

tasks.compileJava {
    dependsOn("verifyGameJar", "verifyZombieBuddyApi")
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
            gameJar.absolutePath,
            sourceSets.test.get().output.classesDirs.asPath,
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

val verifyIsoPlayerShellRuntime by tasks.registering(Exec::class) {
    group = "verification"
    description = "Defines the generated IsoPlayer NPC shell with Project Zomboid's Java runtime."
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
            gameJar.absolutePath,
            sourceSets.test.get().output.classesDirs.asPath,
        ).joinToString(System.getProperty("path.separator"))
        commandLine(
            javaRuntime.absolutePath,
            "-Xverify:all",
            "-cp",
            classpath,
            "com.knoxsurvivors.engine.KnoxIsoPlayerShellVerifier",
        )
    }
}

val verifyCorpseLifecycle by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies that Knox death handoff uses the native reanimation decision."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxNpcRegistryVerifier")
}

val verifyMovementOwnership by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies movement ownership, replacement, release, and recovery state."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxMovementRequestVerifier")
}

val verifyTraversalPolicy by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies native-first obstacle policy, edge suppression, and route continuation."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxTraversalVerifier")
}

val verifyCompanionLocomotion by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies companion walk, run, sprint, downgrade, and condition policy."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxLocomotionVerifier")
}

val verifyMeleeCombatLifecycle by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies terminal melee input, route, and ownership cleanup."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxCombatControllerVerifier")
}

val verifyInventorySnapshot by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies native item payload handoff, bag contents, equipment and legacy inventory migration."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxInventorySnapshotVerifier")
}

// Synthetic verifier failures must never contaminate the player's live log.
tasks.withType<JavaExec>().configureEach {
    systemProperty("knox.logDirectory", layout.buildDirectory.dir("verification-logs/$name").get().asFile.absolutePath)
}
tasks.withType<Test>().configureEach {
    systemProperty("knox.logDirectory", layout.buildDirectory.dir("verification-logs/$name").get().asFile.absolutePath)
}

tasks.check {
    dependsOn(
        verifyCombatTransformer,
        verifyZombieVisibilityTransformer,
        verifyZombieVisibilityRuntime,
        verifyIsoPlayerShellPolicy,
        verifyIsoPlayerShellRuntime,
        verifyCorpseLifecycle,
        verifyMovementOwnership,
        verifyTraversalPolicy,
        verifyCompanionLocomotion,
        verifyMeleeCombatLifecycle,
        verifyInventorySnapshot,
    )
}
