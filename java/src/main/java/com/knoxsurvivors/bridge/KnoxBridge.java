package com.knoxsurvivors.bridge;

import com.knoxsurvivors.agent.KnoxAgent;

/**
 * Single Java object exposed to Project Zomboid Lua.
 *
 * <p>Gameplay capabilities will be added here only after each preceding bridge and lifecycle
 * milestone is verified in game.</p>
 */
public final class KnoxBridge {
    public static final String RUNTIME_VERSION = "0.0.1-dev";

    private long pingCount;

    public synchronized String ping() {
        pingCount++;
        KnoxAgent.writeLog("Lua bridge ping count=" + pingCount);
        return "Knox Survivors Runtime " + RUNTIME_VERSION;
    }

    public String getRuntimeVersion() {
        return RUNTIME_VERSION;
    }

    public boolean isRuntimeLoaded() {
        return true;
    }

    public synchronized long getPingCount() {
        return pingCount;
    }

    @Override
    public synchronized String toString() {
        return "KnoxBridge{version=" + RUNTIME_VERSION + ", pingCount=" + pingCount + "}";
    }
}
