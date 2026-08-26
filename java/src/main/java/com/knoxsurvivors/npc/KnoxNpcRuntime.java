package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;

/** Mutable engine state owned by one persistent Knox survivor identity. */
final class KnoxNpcRuntime {
    private static final float ARRIVAL_DISTANCE = 0.65f;
    private static final int STUCK_WINDOW_TICKS = 45;
    private static final float STUCK_MIN_DISPLACEMENT = 0.12f;

    private KnoxNpc npc;
    private boolean movementRequested;
    private float movementStartX;
    private float movementStartY;
    private float movementTargetX;
    private float movementTargetY;
    private int movementTargetZ;
    private String movementControllerState = "NotStarted";
    private float lastProgressX;
    private float lastProgressY;
    private int noProgressTicks;
    private KnoxSurvivorRecord lastRecord;
    private final KnoxCombatController combatController = new KnoxCombatController();

    KnoxNpcRuntime(KnoxNpc npc) {
        this.npc = npc;
        npc.clearMovementRoute();
    }

    KnoxNpc npc() {
        return npc;
    }

    void replaceNpc(KnoxNpc replacement) {
        combatController.reset();
        npc = replacement;
        resetMovement();
        npc.clearMovementRoute();
    }

    KnoxSurvivorRecord lastRecord() {
        return lastRecord;
    }

    void setLastRecord(KnoxSurvivorRecord record) {
        lastRecord = record;
    }

    KnoxCombatController combat() {
        return combatController;
    }

    String beginMove(Object square, boolean exactAdjacentCrossing) {
        return beginMove(square, exactAdjacentCrossing, "normal");
    }

    String beginMove(Object square, boolean exactAdjacentCrossing, String pace) {
        if (movementRequested) {
            return "MOVE_ALREADY_REQUESTED " + movementDescription();
        }
        try {
            Object body = npc.getBody();
            movementStartX = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
            movementStartY = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
            movementTargetX = ((Number) square.getClass().getMethod("getX").invoke(square)).floatValue()
                + 0.5f;
            movementTargetY = ((Number) square.getClass().getMethod("getY").invoke(square)).floatValue()
                + 0.5f;
            movementTargetZ = ((Number) square.getClass().getMethod("getZ").invoke(square)).intValue();
            lastProgressX = movementStartX;
            lastProgressY = movementStartY;
            noProgressTicks = 0;
            npc.setMovementPace(pace);
            if (exactAdjacentCrossing) {
                KnoxNpcFactory.moveAcrossAdjacentEdge(npc, square);
            } else {
                KnoxNpcFactory.moveTo(npc, square);
                npc.clearMovementRoute();
            }
            movementRequested = true;
            movementControllerState = "Working";
            String result = (exactAdjacentCrossing ? "CROSS_STARTED " : "MOVE_STARTED ")
                + movementDescription();
            KnoxAgent.writeLog("NPC probe " + result);
            return result;
        } catch (Throwable throwable) {
            return failure("MOVE_FAILED", throwable);
        }
    }

    String tickMovement() {
        if (!movementRequested) {
            return "IDLE";
        }
        if (isTerminal(movementControllerState)) {
            return finishMovementRequest(movementControllerState);
        }
        try {
            String previousState = movementControllerState;
            float currentX = ((Number) npc.getBody().getClass().getMethod("getX")
                .invoke(npc.getBody())).floatValue();
            float currentY = ((Number) npc.getBody().getClass().getMethod("getY")
                .invoke(npc.getBody())).floatValue();
            float remainingDistance = distance(currentX, currentY, movementTargetX, movementTargetY);
            movementControllerState = KnoxNpcFactory.tickMovement(
                npc,
                remainingDistance,
                npc.getMovementPace()
            );
            if (isStuckState(movementControllerState) && remainingDistance > ARRIVAL_DISTANCE) {
                float progress = distance(currentX, currentY, lastProgressX, lastProgressY);
                if (progress >= STUCK_MIN_DISPLACEMENT) {
                    lastProgressX = currentX;
                    lastProgressY = currentY;
                    noProgressTicks = 0;
                } else {
                    noProgressTicks++;
                }
                if (noProgressTicks >= STUCK_WINDOW_TICKS) {
                    KnoxNpcFactory.cancelMovement(npc);
                    String result = "FailedStuck displacement="
                        + distance(currentX, currentY, movementStartX, movementStartY)
                        + " targetDistance=" + remainingDistance
                        + " state=" + movementControllerState;
                    KnoxAgent.writeLog("NPC probe movement " + npc.describe() + " " + result);
                    return finishMovementRequest(result);
                }
            } else if (!isStuckState(movementControllerState)) {
                // Turning, climbing, and door/window actions legitimately hold the
                // survivor in place. They are governed by their action timeout rather
                // than being mistaken for a blocked locomotion route.
                noProgressTicks = 0;
                lastProgressX = currentX;
                lastProgressY = currentY;
            }
            if (!movementControllerState.equals(previousState)) {
                KnoxAgent.writeLog(
                    "NPC probe movement controller="
                        + movementControllerState
                        + " "
                        + movementDescription()
                );
            }
            return isTerminal(movementControllerState)
                ? finishMovementRequest(movementControllerState)
                : movementControllerState;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            movementControllerState = "Failed";
            movementRequested = false;
            KnoxAgent.writeLog(
                "ERROR NPC probe movement tick failed "
                    + cause.getClass().getName()
                    + ": "
                    + cause.getMessage()
            );
            return "TICK_FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
        }
    }

    String cancelMovement() {
        try {
            KnoxNpcFactory.cancelMovement(npc);
            resetMovement();
            return "MOVE_CANCELLED " + npc.describe();
        } catch (Throwable throwable) {
            return failure("MOVE_CANCEL_FAILED", throwable);
        }
    }

    boolean hasTraversalEvidence(String state) {
        return npc.hasMovementTraversalEvidence(state);
    }

    String status() {
        try {
            String live = KnoxNpcFactory.describeLive(npc);
            if (!movementRequested) {
                return live + " movement=NOT_REQUESTED";
            }
            Object body = npc.getBody();
            float x = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
            float y = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
            float distance = distance(x, y, movementTargetX, movementTargetY);
            float displacement = distance(x, y, movementStartX, movementStartY);
            String state = distance <= ARRIVAL_DISTANCE ? "ARRIVED" : "IN_PROGRESS";
            return live
                + " movement=" + state
                + " controller=" + movementControllerState
                + " target=" + movementTargetX + "," + movementTargetY + "," + movementTargetZ
                + " distance=" + distance
                + " displacement=" + displacement;
        } catch (Throwable throwable) {
            return failure("STATUS_FAILED", throwable);
        }
    }

    void reset() {
        combatController.reset();
        lastRecord = null;
        resetMovement();
    }

    private void resetMovement() {
        movementRequested = false;
        movementControllerState = "NotStarted";
        lastProgressX = 0.0f;
        lastProgressY = 0.0f;
        noProgressTicks = 0;
        npc.setMovementPace("normal");
    }

    private String finishMovementRequest(String terminalState) {
        movementRequested = false;
        noProgressTicks = 0;
        npc.setMovementPace("normal");
        return terminalState;
    }

    private static boolean isStuckState(String state) {
        return "Working".equals(state)
            || "ManualRoute".equals(state)
            || "Pathfinding".equalsIgnoreCase(state)
            || "PathFind".equalsIgnoreCase(state);
    }

    private String movementDescription() {
        return npc.describe()
            + " from=" + movementStartX + "," + movementStartY
            + " target=" + movementTargetX + "," + movementTargetY + "," + movementTargetZ;
    }

    private static boolean isTerminal(String state) {
        return "Succeeded".equals(state) || state.startsWith("Failed");
    }

    private static float distance(float firstX, float firstY, float secondX, float secondY) {
        float deltaX = firstX - secondX;
        float deltaY = firstY - secondY;
        return (float) Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    }

    private static String failure(String prefix, Throwable throwable) {
        Throwable cause = rootCause(throwable);
        String result = prefix + " " + cause.getClass().getName() + ": " + cause.getMessage();
        KnoxAgent.writeLog("ERROR NPC probe " + result);
        return result;
    }

    private static Throwable rootCause(Throwable throwable) {
        Throwable current = throwable;
        while (current.getCause() != null && current.getCause() != current) {
            current = current.getCause();
        }
        return current;
    }
}
