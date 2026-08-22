package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;

/** Owns the single active NPC allowed during the M1 lifecycle probe. */
public final class KnoxNpcRegistry {
    private static final float ARRIVAL_DISTANCE = 0.65f;

    private KnoxNpc activeNpc;
    private boolean movementRequested;
    private float movementStartX;
    private float movementStartY;
    private float movementTargetX;
    private float movementTargetY;
    private int movementTargetZ;

    public synchronized String spawnOne(Object square) {
        if (activeNpc != null) {
            return "ALREADY_ACTIVE " + activeNpc.describe();
        }

        try {
            activeNpc = KnoxNpcFactory.create("ks-test-1", square);
            movementRequested = false;
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

    public synchronized String moveOne(Object square) {
        if (activeNpc == null) {
            return "MOVE_FAILED NONE_ACTIVE";
        }
        if (movementRequested) {
            return "MOVE_ALREADY_REQUESTED " + movementDescription();
        }

        try {
            Object body = activeNpc.getBody();
            movementStartX = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
            movementStartY = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
            movementTargetX = ((Number) square.getClass().getMethod("getX").invoke(square)).floatValue()
                + 0.5f;
            movementTargetY = ((Number) square.getClass().getMethod("getY").invoke(square)).floatValue()
                + 0.5f;
            movementTargetZ = ((Number) square.getClass().getMethod("getZ").invoke(square)).intValue();
            KnoxNpcFactory.moveTo(activeNpc, square);
            movementRequested = true;
            String result = "MOVE_STARTED " + movementDescription();
            KnoxAgent.writeLog("NPC probe " + result);
            return result;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            String result = "MOVE_FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
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
            String live = KnoxNpcFactory.describeLive(activeNpc);
            if (!movementRequested) {
                return live + " movement=NOT_REQUESTED";
            }

            Object body = activeNpc.getBody();
            float x = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
            float y = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
            float distance = distance(x, y, movementTargetX, movementTargetY);
            float displacement = distance(x, y, movementStartX, movementStartY);
            String state = distance <= ARRIVAL_DISTANCE ? "ARRIVED" : "IN_PROGRESS";
            return live
                + " movement="
                + state
                + " target="
                + movementTargetX
                + ","
                + movementTargetY
                + ","
                + movementTargetZ
                + " distance="
                + distance
                + " displacement="
                + displacement;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            return "STATUS_FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
        }
    }

    private String movementDescription() {
        return activeNpc.describe()
            + " from="
            + movementStartX
            + ","
            + movementStartY
            + " target="
            + movementTargetX
            + ","
            + movementTargetY
            + ","
            + movementTargetZ;
    }

    private static float distance(float firstX, float firstY, float secondX, float secondY) {
        float deltaX = firstX - secondX;
        float deltaY = firstY - secondY;
        return (float) Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    }

    private static Throwable rootCause(Throwable throwable) {
        Throwable current = throwable;
        while (current.getCause() != null && current.getCause() != current) {
            current = current.getCause();
        }
        return current;
    }
}
