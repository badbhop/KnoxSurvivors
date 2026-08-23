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
    private String movementControllerState = "NotStarted";
    private KnoxSurvivorRecord lastRecord;

    public synchronized String spawnOne(Object square) {
        if (activeNpc != null) {
            return "ALREADY_ACTIVE " + activeNpc.describe();
        }

        try {
            activeNpc = KnoxNpcFactory.create("ks-test-1", square);
            activeNpc.clearMovementRoute();
            movementRequested = false;
            movementControllerState = "NotStarted";
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
        return beginMove(square, false);
    }

    public synchronized String crossOneAdjacentEdge(Object square) {
        return beginMove(square, true);
    }

    private String beginMove(Object square, boolean exactAdjacentCrossing) {
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
            if (exactAdjacentCrossing) {
                KnoxNpcFactory.moveAcrossAdjacentEdge(activeNpc, square);
            } else {
                KnoxNpcFactory.moveTo(activeNpc, square);
                activeNpc.clearMovementRoute();
            }
            movementRequested = true;
            movementControllerState = "Working";
            String result = (exactAdjacentCrossing ? "CROSS_STARTED " : "MOVE_STARTED ")
                + movementDescription();
            KnoxAgent.writeLog("NPC probe " + result);
            return result;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            String result = "MOVE_FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
            KnoxAgent.writeLog("ERROR NPC probe " + result);
            return result;
        }
    }

    public synchronized boolean hasTraversalEvidence(String state) {
        return activeNpc != null && activeNpc.hasMovementTraversalEvidence(state);
    }

    public synchronized String tickOne() {
        if (activeNpc == null || !movementRequested) {
            return "IDLE";
        }
        if ("Succeeded".equals(movementControllerState)
            || movementControllerState.startsWith("Failed")) {
            return movementControllerState;
        }

        try {
            String previousState = movementControllerState;
            movementControllerState = KnoxNpcFactory.tickMovement(activeNpc);
            if (!movementControllerState.equals(previousState)) {
                KnoxAgent.writeLog(
                    "NPC probe movement controller="
                        + movementControllerState
                        + " "
                        + movementDescription()
                );
            }
            return movementControllerState;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            movementControllerState = "Failed";
            KnoxAgent.writeLog(
                "ERROR NPC probe movement tick failed "
                    + cause.getClass().getName()
                    + ": "
                    + cause.getMessage()
            );
            return "TICK_FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
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

    public synchronized String seedAndEquipOne() {
        if (activeNpc == null) {
            return "EQUIP_FAILED NONE_ACTIVE";
        }
        try {
            Object body = activeNpc.getBody();
            Object inventory = body.getClass().getMethod("getInventory").invoke(body);
            inventory.getClass().getMethod("AddItem", String.class).invoke(inventory, "Base.Hammer");
            inventory.getClass().getMethod("AddItem", String.class).invoke(inventory, "Base.BaseballBat");
            String equipped = KnoxEquipmentController.equipBestMelee(body);
            lastRecord = captureRecord(activeNpc);
            String result = equipped + " items=" + lastRecord.inventory.size();
            KnoxAgent.writeLog("NPC equipment " + result);
            return result;
        } catch (Throwable throwable) {
            return failure("EQUIP_FAILED", throwable);
        }
    }

    public synchronized boolean isOneFemale() {
        if (activeNpc == null) {
            throw new IllegalStateException("No active NPC");
        }
        try {
            return (Boolean) activeNpc.getBody().getClass().getMethod("isFemale")
                .invoke(activeNpc.getBody());
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("Unable to read NPC gender", exception);
        }
    }

    public synchronized String wearOneItem(String fullType) {
        if (activeNpc == null) {
            return "WEAR_FAILED NONE_ACTIVE";
        }
        try {
            Object body = activeNpc.getBody();
            Object inventory = body.getClass().getMethod("getInventory").invoke(body);
            Object item = inventory.getClass().getMethod("AddItem", String.class)
                .invoke(inventory, fullType);
            if (item == null) {
                return "WEAR_FAILED ITEM_NOT_CREATED " + fullType;
            }
            Object location = item.getClass().getMethod("getBodyLocation").invoke(item);
            if (location == null) {
                location = item.getClass().getMethod("canBeEquipped").invoke(item);
            }
            if (location == null) {
                return "WEAR_FAILED NO_BODY_LOCATION " + fullType;
            }
            invokeCompatible(body, "setWornItem", location, item);
            body.getClass().getMethod("resetModelNextFrame").invoke(body);
            return "WORN " + fullType + " location=" + location;
        } catch (Throwable throwable) {
            return failure("WEAR_FAILED " + fullType, throwable);
        }
    }

    public synchronized String recreateOne() {
        if (activeNpc == null) {
            return "RECREATE_FAILED NONE_ACTIVE";
        }
        try {
            KnoxSurvivorRecord before = captureRecord(activeNpc);
            Object square = activeNpc.getBody().getClass().getMethod("getCurrentSquare")
                .invoke(activeNpc.getBody());
            KnoxNpcFactory.remove(activeNpc);
            activeNpc = KnoxNpcFactory.create(before.id, square);
            before.appearance.restore(activeNpc.getBody());
            before.inventory.restore(activeNpc.getBody());
            KnoxSurvivorRecord after = captureRecord(activeNpc);
            boolean matches = before.encode().equals(after.encode());
            lastRecord = after;
            String result = "RECREATED matches=" + matches
                + " id=" + after.id
                + " location=" + after.x + "," + after.y + "," + after.z
                + " items=" + after.inventory.size()
                + " primary=" + after.inventory.primaryType();
            KnoxAgent.writeLog("NPC persistence " + result);
            return result;
        } catch (Throwable throwable) {
            return failure("RECREATE_FAILED", throwable);
        }
    }

    public synchronized String capturePersistentRecord() {
        try {
            if (activeNpc == null) {
                return "";
            }
            lastRecord = captureRecord(activeNpc);
            return lastRecord.encode();
        } catch (Throwable throwable) {
            return failure("CAPTURE_FAILED", throwable);
        }
    }

    public synchronized String restorePersistentRecord(String encoded, Object square) {
        if (activeNpc != null) {
            return "RESTORE_FAILED ALREADY_ACTIVE";
        }
        try {
            KnoxSurvivorRecord record = KnoxSurvivorRecord.decode(encoded);
            int squareX = ((Number) square.getClass().getMethod("getX").invoke(square)).intValue();
            int squareY = ((Number) square.getClass().getMethod("getY").invoke(square)).intValue();
            int squareZ = ((Number) square.getClass().getMethod("getZ").invoke(square)).intValue();
            if (record.x != squareX || record.y != squareY || record.z != squareZ) {
                return "RESTORE_FAILED LOCATION_MISMATCH";
            }
            activeNpc = KnoxNpcFactory.create(record.id, square);
            record.appearance.restore(activeNpc.getBody());
            record.inventory.restore(activeNpc.getBody());
            lastRecord = captureRecord(activeNpc);
            String result = "RESTORED id=" + record.id
                + " location=" + record.x + "," + record.y + "," + record.z
                + " items=" + record.inventory.size()
                + " primary=" + record.inventory.primaryType()
                + " appearance=" + record.appearance.summary();
            KnoxAgent.writeLog("NPC persistence " + result);
            return result;
        } catch (Throwable throwable) {
            return failure("RESTORE_FAILED", throwable);
        }
    }

    public synchronized int persistentRecordX(String encoded) {
        return KnoxSurvivorRecord.decode(encoded).x;
    }

    public synchronized int persistentRecordY(String encoded) {
        return KnoxSurvivorRecord.decode(encoded).y;
    }

    public synchronized int persistentRecordZ(String encoded) {
        return KnoxSurvivorRecord.decode(encoded).z;
    }

    public synchronized String equipmentStatus() {
        if (activeNpc == null) {
            return "NONE_ACTIVE";
        }
        try {
            KnoxSurvivorRecord record = captureRecord(activeNpc);
            return "ACTIVE id=" + record.id
                + " location=" + record.x + "," + record.y + "," + record.z
                + " items=" + record.inventory.size()
                + " primary=" + record.inventory.primaryType();
        } catch (Throwable throwable) {
            return failure("STATUS_FAILED", throwable);
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
                + " controller="
                + movementControllerState
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

    public synchronized void abandonForEnvironmentChange() {
        if (activeNpc == null) {
            return;
        }

        String description = activeNpc.describe();
        activeNpc = null;
        lastRecord = null;
        movementRequested = false;
        movementControllerState = "NotStarted";
        KnoxAgent.writeLog(
            "NPC probe ABANDONED_STALE_REFERENCE "
                + description
                + " environmentChanged=true"
        );
    }

    private static KnoxSurvivorRecord captureRecord(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        Object square = body.getClass().getMethod("getCurrentSquare").invoke(body);
        if (square == null) {
            throw new IllegalStateException("NPC has no current square to persist");
        }
        int x = ((Number) square.getClass().getMethod("getX").invoke(square)).intValue();
        int y = ((Number) square.getClass().getMethod("getY").invoke(square)).intValue();
        int z = ((Number) square.getClass().getMethod("getZ").invoke(square)).intValue();
        return new KnoxSurvivorRecord(
            npc.getId(),
            x,
            y,
            z,
            KnoxAppearanceSnapshot.capture(body),
            KnoxInventorySnapshot.capture(body)
        );
    }

    private static Object invokeCompatible(
        Object target,
        String name,
        Object firstArgument,
        Object secondArgument
    ) throws ReflectiveOperationException {
        for (java.lang.reflect.Method method : target.getClass().getMethods()) {
            if (!method.getName().equals(name) || method.getParameterCount() != 2) {
                continue;
            }
            Class<?>[] types = method.getParameterTypes();
            if (types[0].isInstance(firstArgument) && types[1].isInstance(secondArgument)) {
                return method.invoke(target, firstArgument, secondArgument);
            }
        }
        throw new NoSuchMethodException(target.getClass().getName() + "." + name);
    }

    private static String failure(String prefix, Throwable throwable) {
        Throwable cause = rootCause(throwable);
        String result = prefix + " " + cause.getClass().getName() + ": " + cause.getMessage();
        KnoxAgent.writeLog("ERROR NPC probe " + result);
        return result;
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
