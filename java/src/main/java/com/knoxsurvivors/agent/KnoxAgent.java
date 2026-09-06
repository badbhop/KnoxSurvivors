package com.knoxsurvivors.agent;

import com.knoxsurvivors.bridge.KnoxBridgeBootstrap;
import java.io.IOException;
import java.lang.instrument.Instrumentation;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;

/**
 * Java-agent entry point for engine integration that cannot be implemented through Lua alone.
 *
 * <p>The agent installs narrowly scoped engine integrations before the affected game classes are
 * loaded, records startup evidence, and verifies that the expected IsoPlayer class is present.</p>
 */
public final class KnoxAgent {
    private static final String LOG_NAME = "KnoxIsoPlayer.log";

    private KnoxAgent() {
    }

    public static void premain(String arguments, Instrumentation instrumentation) {
        writeLog("agent start arguments=" + String.valueOf(arguments));

        if ("pz-game".equals(arguments)) {
            instrumentation.addTransformer(new KnoxSwipeStateTransformer(), false);
            instrumentation.addTransformer(new KnoxZombieVisibilityTransformer(), false);
            writeLog("combat callback transformer installed");
            writeLog("zombie visibility transformer installed");
        }

        try {
            Class.forName("zombie.characters.IsoPlayer", false, ClassLoader.getSystemClassLoader());
            writeLog("verified class zombie.characters.IsoPlayer");
        } catch (ClassNotFoundException exception) {
            writeLog("ERROR missing zombie.characters.IsoPlayer: " + exception);
        }

        if ("pz-game".equals(arguments)) {
            KnoxBridgeBootstrap.start(instrumentation);
        }
    }

    public static void agentmain(String arguments, Instrumentation instrumentation) {
        premain(arguments, instrumentation);
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
