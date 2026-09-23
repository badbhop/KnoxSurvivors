package com.knoxsurvivors.agent;

import com.knoxsurvivors.bridge.KnoxBridgeBootstrap;
import java.io.IOException;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Knox Survivors engine integration bootstrap.
 *
 * <p>The preferred runtime is now ZombieBuddy. ZombieBuddy loads Knox as a normal Java mod,
 * then {@link #startFromZombieBuddy()} reuses ZombieBuddy's Instrumentation handle to install
 * Knox's existing narrowly-scoped transformers. The legacy premain/agentmain entry points are
 * retained temporarily so an old developer launch path fails safely rather than loading Knox
 * twice during migration.</p>
 */
public final class KnoxAgent {
    private static final String LOG_NAME = "KnoxIsoPlayer.log";
    private static final String GAME_MODE = "pz-game";
    private static final String ZOMBIE_BUDDY_LOADER = "me.zed_0xff.zombie_buddy.Loader";
    private static final Set<String> RETRANSFORM_TARGETS = Set.of(
        "zombie.ai.states.SwipeStatePlayer",
        "zombie.CombatManager",
        "zombie.characters.IsoZombie"
    );
    private static final AtomicBoolean STARTED = new AtomicBoolean(false);

    private KnoxAgent() {
    }

    /** Legacy Java-agent entry point kept only for migration/backward-compatible developer use. */
    public static void premain(String arguments, Instrumentation instrumentation) {
        startRuntime("legacy-javaagent", arguments, instrumentation, false);
    }

    /** Legacy dynamic-attach entry point. Retransformation is required because the game is live. */
    public static void agentmain(String arguments, Instrumentation instrumentation) {
        startRuntime("legacy-agentmain", arguments, instrumentation, true);
    }

    /**
     * Called by com.knoxsurvivors.Main after ZombieBuddy loads the Knox JAR from mod.info.
     */
    public static void startFromZombieBuddy() {
        try {
            Class<?> loaderClass = Class.forName(ZOMBIE_BUDDY_LOADER);
            Method getter = loaderClass.getMethod("getInstrumentation");
            Object value = getter.invoke(null);
            if (!(value instanceof Instrumentation instrumentation)) {
                writeLog("ERROR ZombieBuddy instrumentation handle is unavailable");
                return;
            }
            startRuntime("zombie-buddy", GAME_MODE, instrumentation, true);
        } catch (InvocationTargetException exception) {
            Throwable cause = exception.getCause() == null ? exception : exception.getCause();
            writeLog(
                "ERROR ZombieBuddy instrumentation lookup failed: "
                    + cause.getClass().getName()
                    + ": "
                    + cause.getMessage()
            );
        } catch (ReflectiveOperationException | LinkageError exception) {
            writeLog(
                "ERROR ZombieBuddy is not available to Knox Survivors: "
                    + exception.getClass().getName()
                    + ": "
                    + exception.getMessage()
            );
        }
    }

    private static void startRuntime(
        String source,
        String arguments,
        Instrumentation instrumentation,
        boolean retransformLoadedTargets
    ) {
        writeLog(
            "runtime bootstrap source="
                + source
                + " arguments="
                + String.valueOf(arguments)
        );

        if (!GAME_MODE.equals(arguments)) {
            writeLog("runtime bootstrap ignored because mode is not " + GAME_MODE);
            return;
        }
        if (instrumentation == null) {
            writeLog("ERROR runtime bootstrap received null Instrumentation");
            return;
        }
        if (!STARTED.compareAndSet(false, true)) {
            writeLog("runtime already started; duplicate bootstrap ignored source=" + source);
            return;
        }

        boolean canRetransform = retransformLoadedTargets
            && instrumentation.isRetransformClassesSupported();
        if (retransformLoadedTargets && !canRetransform) {
            writeLog(
                "ERROR runtime source="
                    + source
                    + " does not support class retransformation; loaded combat classes may not patch"
            );
        }

        try {
            instrumentation.addTransformer(new KnoxSwipeStateTransformer(), canRetransform);
            instrumentation.addTransformer(new KnoxZombieVisibilityTransformer(), canRetransform);
            writeLog("combat callback transformer installed retransform=" + canRetransform);
            writeLog("zombie visibility transformer installed retransform=" + canRetransform);

            if (canRetransform) {
                retransformLoadedTargets(instrumentation);
            }

            verifyIsoPlayerClass();
            KnoxBridgeBootstrap.start(instrumentation);
            writeLog("runtime start PASS source=" + source);
        } catch (Throwable throwable) {
            writeLog(
                "ERROR runtime start source="
                    + source
                    + " "
                    + throwable.getClass().getName()
                    + ": "
                    + throwable.getMessage()
            );
        }
    }

    private static void retransformLoadedTargets(Instrumentation instrumentation) {
        int loadedTargets = 0;
        int requested = 0;

        for (Class<?> loadedClass : instrumentation.getAllLoadedClasses()) {
            if (!RETRANSFORM_TARGETS.contains(loadedClass.getName())) {
                continue;
            }
            loadedTargets++;

            if (!instrumentation.isModifiableClass(loadedClass)) {
                writeLog("ERROR target class is not modifiable: " + loadedClass.getName());
                continue;
            }

            try {
                instrumentation.retransformClasses(loadedClass);
                requested++;
                writeLog("retransform PASS class=" + loadedClass.getName());
            } catch (Throwable throwable) {
                writeLog(
                    "ERROR retransform class="
                        + loadedClass.getName()
                        + " "
                        + throwable.getClass().getName()
                        + ": "
                        + throwable.getMessage()
                );
            }
        }

        writeLog(
            "retransform scan complete targetsLoaded="
                + loadedTargets
                + " requested="
                + requested
        );
    }

    private static void verifyIsoPlayerClass() {
        try {
            ClassLoader loader = Thread.currentThread().getContextClassLoader();
            if (loader == null) {
                loader = ClassLoader.getSystemClassLoader();
            }
            Class.forName("zombie.characters.IsoPlayer", false, loader);
            writeLog("verified class zombie.characters.IsoPlayer");
        } catch (ClassNotFoundException exception) {
            writeLog("ERROR missing zombie.characters.IsoPlayer: " + exception);
        }
    }

    public static void writeLog(String message) {
        String line = Instant.now() + " [KnoxSurvivors] " + message + System.lineSeparator();

        try {
            String logDirectory = System.getProperty("knox.logDirectory");
            Path logFile = (logDirectory == null || logDirectory.isBlank()
                ? Path.of(System.getProperty("user.home"), "Zomboid")
                : Path.of(logDirectory)).resolve(LOG_NAME);
            Files.createDirectories(logFile.getParent());
            Files.writeString(
                logFile,
                line,
                StandardCharsets.UTF_8,
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND
            );
        } catch (IOException | java.nio.file.InvalidPathException exception) {
            System.err.print(line);
            exception.printStackTrace(System.err);
        }
    }
}
