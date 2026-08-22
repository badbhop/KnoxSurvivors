package com.knoxsurvivors.bridge;

import com.knoxsurvivors.agent.KnoxAgent;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.util.Collection;

/** Exposes the Knox bridge only after Project Zomboid has initialized a stable Lua environment. */
public final class KnoxBridgeBootstrap {
    private static final String LUA_MANAGER_CLASS = "zombie.Lua.LuaManager";
    private static final long DEADLINE_MILLIS = 120_000L;
    private static final long POLL_MILLIS = 250L;
    private static final int REQUIRED_STABLE_POLLS = 4;
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
        int previousLoadedCount = -1;
        int stablePolls = 0;

        while (System.currentTimeMillis() < deadline) {
            try {
                Class<?> luaManagerClass = findLuaManagerClass(instrumentation);
                if (luaManagerClass == null) {
                    sleep();
                    continue;
                }

                Object environment = luaManagerClass.getField("env").get(null);
                Object exposer = luaManagerClass.getField("exposer").get(null);
                Object loaded = luaManagerClass.getField("loaded").get(null);
                Object exposerEnvironment = exposer == null
                    ? null
                    : getInheritedField(exposer, "environment");
                int loadedCount = loaded instanceof Collection<?>
                    ? ((Collection<?>) loaded).size()
                    : 0;
                if (environment == null
                    || exposer == null
                    || exposerEnvironment != environment
                    || loadedCount == 0) {
                    previousEnvironment = null;
                    previousExposer = null;
                    previousLoadedCount = -1;
                    stablePolls = 0;
                    sleep();
                    continue;
                }

                if (environment != previousEnvironment
                    || exposer != previousExposer
                    || loadedCount != previousLoadedCount) {
                    previousEnvironment = environment;
                    previousExposer = exposer;
                    previousLoadedCount = loadedCount;
                    stablePolls = 0;
                    sleep();
                    continue;
                }

                stablePolls++;
                if (stablePolls < REQUIRED_STABLE_POLLS) {
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
                Throwable cause = unwrapInvocationTarget(throwable);
                KnoxAgent.writeLog(
                    "Lua bridge exposure attempt failed: "
                        + cause.getClass().getName()
                        + ": "
                        + cause.getMessage()
                );
            }

            sleep();
        }

        KnoxAgent.writeLog("ERROR Lua bridge exposure deadline reached");
    }

    private static Throwable unwrapInvocationTarget(Throwable throwable) {
        Throwable current = throwable;
        while (current instanceof InvocationTargetException
            && ((InvocationTargetException) current).getCause() != null) {
            current = ((InvocationTargetException) current).getCause();
        }
        return current;
    }

    private static Object getInheritedField(Object target, String fieldName)
        throws ReflectiveOperationException {
        Class<?> current = target.getClass();
        while (current != null) {
            try {
                Field field = current.getDeclaredField(fieldName);
                field.setAccessible(true);
                return field.get(target);
            } catch (NoSuchFieldException notOnThisClass) {
                current = current.getSuperclass();
            }
        }
        throw new NoSuchFieldException(fieldName);
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
