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

/** Knox Survivors engine integration bootstrap. */
public final class KnoxAgent {
    private static final String LOG_NAME = "KnoxIsoPlayer.log";
    private static final String GAME_MODE = "pz-game";
    private static final String ZB_V2_PATCH_API = "me.zed_0xff.zombie_buddy.Patch";
    private static final String ZB_LOADER = "me.zed_0xff.zombie_buddy.Loader";
    private static final Set<String> RETRANSFORM_TARGETS = Set.of(
        "zombie.ai.states.SwipeStatePlayer",
        "zombie.CombatManager",
        "zombie.characters.IsoZombie"
    );
    private static final AtomicBoolean STARTED = new AtomicBoolean(false);
    private static volatile String runtimeSource = "none";

    private KnoxAgent() { }

    /** Legacy Knox Launcher / direct -javaagent entry point. */
    public static void premain(String arguments, Instrumentation instrumentation) {
        startRuntime("legacy-javaagent", arguments, instrumentation, false);
    }

    /** Legacy dynamic-attach entry point. */
    public static void agentmain(String arguments, Instrumentation instrumentation) {
        startRuntime("legacy-agentmain", arguments, instrumentation, true);
    }

    /**
     * ZombieBuddy Java-mod entry point.
     *
     * Released ZombieBuddy 2.x intentionally keeps Instrumentation private. Knox therefore
     * uses its supported @Patch API on 2.x. A future ZombieBuddy build that exposes the
     * official Loader.getInstrumentation() API can still use Knox's original transformers.
     */
    public static void startFromZombieBuddy() {
        if (classAvailable(ZB_V2_PATCH_API)) {
            startZombieBuddyPatchRuntime();
            return;
        }

        // Future/alternate official API path. Never reflect into private/package fields.
        try {
            Class<?> loaderClass = Class.forName(ZB_LOADER);
            Method getter = loaderClass.getMethod("getInstrumentation");
            Object value = getter.invoke(null);
            if (!(value instanceof Instrumentation instrumentation)) {
                writeLog("ERROR ZombieBuddy instrumentation handle is unavailable");
                return;
            }
            startRuntime("zombie-buddy-instrumentation", GAME_MODE, instrumentation, true);
        } catch (InvocationTargetException exception) {
            Throwable cause = exception.getCause() == null ? exception : exception.getCause();
            writeLog("ERROR ZombieBuddy instrumentation lookup failed: "
                + cause.getClass().getName() + ": " + cause.getMessage());
        } catch (NoSuchMethodException exception) {
            writeLog("ERROR ZombieBuddy does not expose a supported Knox runtime API. "
                + "Use ZombieBuddy 2.3.2+ with its Patch API or use the Knox Survivors Launcher.");
        } catch (ReflectiveOperationException | LinkageError exception) {
            writeLog("ERROR ZombieBuddy is not available to Knox Survivors: "
                + exception.getClass().getName() + ": " + exception.getMessage());
        }
    }

    private static void startZombieBuddyPatchRuntime() {
        writeLog("runtime bootstrap source=zombie-buddy-patch-api arguments=" + GAME_MODE);
        if (!STARTED.compareAndSet(false, true)) {
            writeLog("runtime already started; duplicate bootstrap ignored source=zombie-buddy-patch-api");
            return;
        }
        runtimeSource = "zombie-buddy-patch-api";
        try {
            KnoxBridgeBootstrap.startWithoutInstrumentation();
            writeLog("ZombieBuddy Patch API mode armed; waiting for patch application marker");
            writeLog("runtime start PASS source=zombie-buddy-patch-api");
        } catch (Throwable throwable) {
            writeLog("ERROR runtime start source=zombie-buddy-patch-api "
                + throwable.getClass().getName() + ": " + throwable.getMessage());
        }
    }

    private static boolean classAvailable(String className) {
        try {
            ClassLoader loader = Thread.currentThread().getContextClassLoader();
            if (loader == null) loader = ClassLoader.getSystemClassLoader();
            Class.forName(className, false, loader);
            return true;
        } catch (ClassNotFoundException | LinkageError unavailable) {
            return false;
        }
    }

    public static boolean isLegacyRuntimeActive() {
        return runtimeSource.startsWith("legacy-");
    }

    public static boolean isZombieBuddyPatchRuntime() {
        return "zombie-buddy-patch-api".equals(runtimeSource);
    }

    public static String getRuntimeSource() {
        return runtimeSource;
    }

    private static void startRuntime(
        String source,
        String arguments,
        Instrumentation instrumentation,
        boolean retransformLoadedTargets
    ) {
        writeLog("runtime bootstrap source=" + source + " arguments=" + String.valueOf(arguments));

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
        runtimeSource = source;

        boolean canRetransform = retransformLoadedTargets
            && instrumentation.isRetransformClassesSupported();
        if (retransformLoadedTargets && !canRetransform) {
            writeLog("ERROR runtime source=" + source
                + " does not support class retransformation; loaded combat classes may not patch");
        }

        try {
            instrumentation.addTransformer(new KnoxSwipeStateTransformer(), canRetransform);
            instrumentation.addTransformer(new KnoxZombieVisibilityTransformer(), canRetransform);
            writeLog("combat callback transformer installed retransform=" + canRetransform);
            writeLog("zombie visibility transformer installed retransform=" + canRetransform);

            if (canRetransform) retransformLoadedTargets(instrumentation);

            verifyIsoPlayerClass();
            KnoxBridgeBootstrap.start(instrumentation);
            writeLog("runtime start PASS source=" + source);
        } catch (Throwable throwable) {
            writeLog("ERROR runtime start source=" + source + " "
                + throwable.getClass().getName() + ": " + throwable.getMessage());
        }
    }

    private static void retransformLoadedTargets(Instrumentation instrumentation) {
        int loadedTargets = 0;
        int requested = 0;
        for (Class<?> loadedClass : instrumentation.getAllLoadedClasses()) {
            if (!RETRANSFORM_TARGETS.contains(loadedClass.getName())) continue;
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
                writeLog("ERROR retransform class=" + loadedClass.getName() + " "
                    + throwable.getClass().getName() + ": " + throwable.getMessage());
            }
        }
        writeLog("retransform scan complete targetsLoaded=" + loadedTargets + " requested=" + requested);
    }

    private static void verifyIsoPlayerClass() {
        try {
            ClassLoader loader = Thread.currentThread().getContextClassLoader();
            if (loader == null) loader = ClassLoader.getSystemClassLoader();
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
            Files.writeString(logFile, line, StandardCharsets.UTF_8,
                StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (IOException | java.nio.file.InvalidPathException exception) {
            System.err.print(line);
            exception.printStackTrace(System.err);
        }
    }
}
