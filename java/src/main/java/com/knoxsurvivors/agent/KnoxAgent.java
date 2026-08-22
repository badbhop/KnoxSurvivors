package com.knoxsurvivors.agent;

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
 * <p>The foundation milestone intentionally installs no transformers. It records that the agent
 * started and that the installed game exposes the expected IsoPlayer class without initializing
 * game state prematurely.</p>
 */
public final class KnoxAgent {
    private static final String LOG_NAME = "KnoxIsoPlayer.log";

    private KnoxAgent() {
    }

    public static void premain(String arguments, Instrumentation instrumentation) {
        writeLog("agent start arguments=" + String.valueOf(arguments));

        try {
            Class.forName("zombie.characters.IsoPlayer", false, ClassLoader.getSystemClassLoader());
            writeLog("verified class zombie.characters.IsoPlayer");
        } catch (ClassNotFoundException exception) {
            writeLog("ERROR missing zombie.characters.IsoPlayer: " + exception);
        }
    }

    public static void agentmain(String arguments, Instrumentation instrumentation) {
        premain(arguments, instrumentation);
    }

    private static void writeLog(String message) {
        Path logFile = Path.of(System.getProperty("user.home"), "Zomboid", LOG_NAME);
        String line = Instant.now() + " [KnoxSurvivors] " + message + System.lineSeparator();

        try {
            Files.createDirectories(logFile.getParent());
            Files.writeString(
                logFile,
                line,
                StandardCharsets.UTF_8,
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND
            );
        } catch (IOException exception) {
            System.err.print(line);
            exception.printStackTrace(System.err);
        }
    }
}
