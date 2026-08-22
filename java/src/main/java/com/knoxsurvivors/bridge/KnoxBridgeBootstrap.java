package com.knoxsurvivors.bridge;

import com.knoxsurvivors.agent.KnoxAgent;
import java.lang.instrument.Instrumentation;

/** Exposes the Knox bridge only after Project Zomboid has initialized a stable Lua environment. */
public final class KnoxBridgeBootstrap {
    private static final String LUA_MANAGER_CLASS = "zombie.Lua.LuaManager";
    private static final long DEADLINE_MILLIS = 120_000L;
    private static final long POLL_MILLIS = 250L;
    private static final KnoxBridge BRIDGE = new KnoxBridge();

    private KnoxBridgeBootstrap() {
    }

    public static void start(Instrumentation instrumentation) {
        Thread watchdog = new Thread(
            () -> exposeWhenReady(instrumentation),
            "KnoxSurvivors-LuaBridge"
        );
        watchdog.setDaemon(true);
        watchdog.start();
        KnoxAgent.writeLog("Lua bridge watchdog started");
    }

    private static void exposeWhenReady(Instrumentation instrumentation) {
        long deadline = System.currentTimeMillis() + DEADLINE_MILLIS;
        Object previousEnvironment = null;
        Object previousExposer = null;

        while (System.currentTimeMillis() < deadline) {
            try {
                Class<?> luaManagerClass = findLuaManagerClass(instrumentation);
                if (luaManagerClass == null) {
                    sleep();
                    continue;
                }

                Object environment = luaManagerClass.getField("env").get(null);
                Object exposer = luaManagerClass.getField("exposer").get(null);
                if (environment == null || exposer == null) {
                    previousEnvironment = null;
                    previousExposer = null;
                    sleep();
                    continue;
                }

                if (environment != previousEnvironment || exposer != previousExposer) {
                    previousEnvironment = environment;
                    previousExposer = exposer;
                    sleep();
                    continue;
                }

                exposer.getClass().getMethod("setExposed", Class.class)
                    .invoke(exposer, KnoxBridge.class);
                exposer.getClass().getMethod("exposeLikeJava", Class.class)
                    .invoke(exposer, KnoxBridge.class);
                environment.getClass().getMethod("rawset", Object.class, Object.class)
                    .invoke(environment, "KnoxJavaBridge", BRIDGE);

                Object exposedBridge = environment.getClass().getMethod("rawget", Object.class)
                    .invoke(environment, "KnoxJavaBridge");
                if (exposedBridge == BRIDGE) {
                    KnoxAgent.writeLog("Lua bridge exposed global=KnoxJavaBridge");
                    return;
                }
            } catch (Throwable throwable) {
                KnoxAgent.writeLog(
                    "Lua bridge exposure attempt failed: "
                        + throwable.getClass().getName()
                        + ": "
                        + throwable.getMessage()
                );
            }

            sleep();
        }

        KnoxAgent.writeLog("ERROR Lua bridge exposure deadline reached");
    }

    private static Class<?> findLuaManagerClass(Instrumentation instrumentation) {
        for (Class<?> loadedClass : instrumentation.getAllLoadedClasses()) {
            if (LUA_MANAGER_CLASS.equals(loadedClass.getName())) {
                return loadedClass;
            }
        }
        return null;
    }

    private static void sleep() {
        try {
            Thread.sleep(POLL_MILLIS);
        } catch (InterruptedException interruptedException) {
            Thread.currentThread().interrupt();
        }
    }
}
