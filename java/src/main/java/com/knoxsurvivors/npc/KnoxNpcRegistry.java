package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;

/** Owns the single active NPC allowed during the M1 lifecycle probe. */
public final class KnoxNpcRegistry {
    private KnoxNpc activeNpc;

    public synchronized String spawnOne(Object square) {
        if (activeNpc != null) {
            return "ALREADY_ACTIVE " + activeNpc.describe();
        }

        try {
            activeNpc = KnoxNpcFactory.create("ks-test-1", square);
            String result = "SPAWNED " + activeNpc.describe() + " localSlotsUnchanged=true";
            KnoxAgent.writeLog("NPC probe " + result);
            return result;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            String result = "FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
            KnoxAgent.writeLog("ERROR NPC probe " + result);
            return result;
        }
    }

    public synchronized String removeOne() {
        if (activeNpc == null) {
            return "NONE_ACTIVE";
        }

        String description = activeNpc.describe();
        try {
            KnoxNpcFactory.remove(activeNpc);
            KnoxAgent.writeLog("NPC probe REMOVED " + description);
            return "REMOVED " + description;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            KnoxAgent.writeLog(
                "ERROR NPC probe removal failed "
                    + cause.getClass().getName()
                    + ": "
                    + cause.getMessage()
            );
            return "REMOVE_FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
        } finally {
            activeNpc = null;
        }
    }

    public synchronized String status() {
        if (activeNpc == null) {
            return "NONE_ACTIVE";
        }
        try {
            return KnoxNpcFactory.describeLive(activeNpc);
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            return "STATUS_FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
        }
    }

    private static Throwable rootCause(Throwable throwable) {
        Throwable current = throwable;
        while (current.getCause() != null && current.getCause() != current) {
            current = current.getCause();
        }
        return current;
    }
}
