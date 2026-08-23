package com.knoxsurvivors.npc;

import com.knoxsurvivors.engine.KnoxIsoPlayerShellDefinition;
import java.lang.reflect.Array;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/** Constructs the smallest off-slot IsoPlayer body needed for the M1 lifecycle probe. */
final class KnoxNpcFactory {
    private static final String ISO_PLAYER_CLASS = "zombie.characters.IsoPlayer";
    private static final String GRID_SQUARE_CLASS = "zombie.iso.IsoGridSquare";

    private KnoxNpcFactory() {
    }

    static KnoxNpc create(String id, Object square) throws ReflectiveOperationException {
        requireClass(square, GRID_SQUARE_CLASS, "spawn square");

        ClassLoader loader = square.getClass().getClassLoader();
        Class<?> isoPlayerClass = Class.forName(ISO_PLAYER_CLASS, false, loader);
        Class<?> isoPlayerShellClass = KnoxIsoPlayerShellDefinition.getOrDefine(loader);
        Class<?> isoCellClass = Class.forName("zombie.iso.IsoCell", false, loader);
        Class<?> survivorDescClass = Class.forName("zombie.characters.SurvivorDesc", false, loader);
        Class<?> survivorFactoryClass = Class.forName(
            "zombie.characters.SurvivorFactory",
            false,
            loader
        );
        Class<?> modelManagerClass = Class.forName(
            "zombie.core.skinnedmodel.ModelManager",
            false,
            loader
        );

        Object[] localPlayersBefore = snapshotLocalPlayers(isoPlayerClass);
        Object cell = invoke(square, "getCell");
        int x = ((Number) invoke(square, "getX")).intValue();
        int y = ((Number) invoke(square, "getY")).intValue();
        int z = ((Number) invoke(square, "getZ")).intValue();
        Object descriptor = survivorFactoryClass.getMethod("CreateSurvivor").invoke(null);

        Constructor<?> constructor = isoPlayerShellClass.getConstructor(
            isoCellClass,
            survivorDescClass,
            int.class,
            int.class,
            int.class,
            boolean.class
        );
        Object body = constructor.newInstance(cell, descriptor, x, y, z, false);

        isoPlayerClass.getMethod("setNpc", boolean.class).invoke(body, true);
        isoPlayerClass.getField("remote").setBoolean(body, false);
        isoPlayerClass.getField("playerIndex").setInt(body, 0);
        isoPlayerClass.getField("serverPlayerIndex").setInt(body, -1);
        isoPlayerClass.getMethod("setOnlineID", short.class).invoke(body, (short) -1);
        isoPlayerClass.getMethod("setUsername", String.class).invoke(body, "Knox Survivor");

        invoke(body, "setCurrent", square.getClass(), square);
        invoke(body, "setMovingSquareNow");
        invoke(body, "setZombiesDontAttack", boolean.class, true);
        invoke(body, "dressInRandomNonSillyOutfit");
        invoke(body, "setAlphaAndTarget", float.class, 1.0f);
        invoke(cell, "addMovingObject", classFor(body, "zombie.iso.IsoMovingObject"), body);
        Object modelManager = modelManagerClass.getField("instance").get(null);
        invoke(modelManager, "Add", classFor(body, "zombie.characters.IsoGameCharacter"), body);
        applyTestMarker(body);

        if (!sameLocalPlayers(localPlayersBefore, snapshotLocalPlayers(isoPlayerClass))) {
            safelyRemove(body);
            throw new IllegalStateException("IsoPlayer local-player slots changed during NPC creation");
        }

        return new KnoxNpc(id, body, x, y, z);
    }

    static void remove(KnoxNpc npc) throws ReflectiveOperationException {
        safelyRemove(npc.getBody());
    }

    static void moveTo(KnoxNpc npc, Object square) throws ReflectiveOperationException {
        requireClass(square, GRID_SQUARE_CLASS, "movement target square");
        float x = ((Number) invoke(square, "getX")).floatValue() + 0.5f;
        float y = ((Number) invoke(square, "getY")).floatValue() + 0.5f;
        float z = ((Number) invoke(square, "getZ")).floatValue();
        invoke(
            npc.getBody(),
            "pathToLocationF",
            float.class,
            float.class,
            float.class,
            x,
            y,
            z
        );
    }

    static String tickMovement(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        Object pathfinder = invoke(body, "getPathFindBehavior2");

        if (npc.hasMovementRoute()) {
            return driveCapturedRoute(npc);
        }

        Object result = invoke(pathfinder, "update");
        String state = result instanceof Enum<?> ? ((Enum<?>) result).name() : String.valueOf(result);
        if ("Working".equals(state)) {
            if (captureEngineRoute(npc, body, pathfinder)) {
                return driveCapturedRoute(npc);
            }
            clearHumanMovementIntent(body);
        } else {
            clearHumanMovementIntent(body);
        }
        return state;
    }

    static String describeLive(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        applyTestMarker(body);
        Object cell = invoke(body, "getCell");
        Object currentSquare = invoke(body, "getCurrentSquare");
        Object movingSquare = invoke(body, "getMovingSquare");
        boolean inCell = ((java.util.Collection<?>) invoke(cell, "getObjectList")).contains(body);
        boolean inSquare = movingSquare != null
            && ((java.util.Collection<?>) invoke(movingSquare, "getMovingObjects")).contains(body);
        float x = ((Number) invoke(body, "getX")).floatValue();
        float y = ((Number) invoke(body, "getY")).floatValue();
        float alpha = ((Number) invoke(body, "getAlpha")).floatValue();
        boolean activeModel = (Boolean) invoke(body, "hasActiveModel");
        Object pathfinder = invoke(body, "getPathFindBehavior2");
        boolean pathing = (Boolean) invoke(body, "isPathing");
        boolean pathRunning = (Boolean) invoke(body, "isPathfindRunning");
        boolean movingUsingPath = (Boolean) invoke(pathfinder, "isMovingUsingPathFind");
        boolean pathAttached = invoke(body, "getPath2") != null;
        boolean localSlotsSafe = !isInLocalPlayerSlots(body);
        boolean localPlayer = (Boolean) invoke(body, "isLocalPlayer");
        boolean deferredMovement = (Boolean) invoke(body, "isDeferredMovementEnabled");
        boolean animationUpdating = (Boolean) invoke(body, "isAnimationUpdatingThisFrame");
        Class<?> gameClientClass = classFor(body, "zombie.network.GameClient");
        boolean gameClient = gameClientClass.getField("client").getBoolean(null);
        boolean remote = classFor(body, ISO_PLAYER_CLASS).getField("remote").getBoolean(body);
        int playerIndex = classFor(body, ISO_PLAYER_CLASS).getField("playerIndex").getInt(body);
        Object moveDirection = classFor(body, ISO_PLAYER_CLASS).getField("playerMoveDir").get(body);
        float moveX = moveDirection.getClass().getField("x").getFloat(moveDirection);
        float moveY = moveDirection.getClass().getField("y").getFloat(moveDirection);
        Object inputComponent = invoke(body, "getCharacterInputComponent");
        Object aiComponent = getAiComponent(body);
        float strafeX = 0.0f;
        float strafeY = 0.0f;
        if (aiComponent != null) {
            Object controlVars = invoke(aiComponent, "getHumanControlVars");
            if (controlVars != null) {
                strafeX = controlVars.getClass().getField("strafeX").getFloat(controlVars);
                strafeY = controlVars.getClass().getField("strafeY").getFloat(controlVars);
            }
        }
        return "ACTIVE "
            + npc.describe()
            + " class="
            + body.getClass().getName()
            + " live="
            + x
            + ","
            + y
            + " current="
            + (currentSquare != null)
            + " moving="
            + (movingSquare != null)
            + " inCell="
            + inCell
            + " inSquare="
            + inSquare
            + " model="
            + activeModel
            + " alpha="
            + alpha
            + " pathing="
            + pathing
            + " pathRunning="
            + pathRunning
            + " movingUsingPath="
            + movingUsingPath
            + " pathAttached="
            + pathAttached
            + " localSlotsSafe="
            + localSlotsSafe
            + " localPlayer="
            + localPlayer
            + " remote="
            + remote
            + " playerIndex="
            + playerIndex
            + " moveDir="
            + moveX
            + ","
            + moveY
            + " strafe="
            + strafeX
            + ","
            + strafeY
            + " inputComponent="
            + (inputComponent != null)
            + " aiComponent="
            + (aiComponent != null)
            + " deferredMovement="
            + deferredMovement
            + " animationUpdating="
            + animationUpdating
            + " gameClient="
            + gameClient
            + " route="
            + npc.describeMovementRoute();
    }

    private static boolean captureEngineRoute(KnoxNpc npc, Object body, Object pathfinder)
        throws ReflectiveOperationException {
        Object path = invoke(body, "getPath2");
        if (path == null) {
            return false;
        }

        int size = ((Number) invoke(path, "size")).intValue();
        if (size <= 0) {
            return false;
        }

        List<float[]> nodes = new ArrayList<>(size);
        for (int index = 0; index < size; index++) {
            Object node = invoke(path, "getNode", int.class, index);
            nodes.add(
                new float[] {
                    node.getClass().getField("x").getFloat(node),
                    node.getClass().getField("y").getFloat(node),
                    node.getClass().getField("z").getFloat(node),
                }
            );
        }

        invoke(pathfinder, "cancel");
        invoke(body, "setPath2", classFor(body, "zombie.pathfind.Path"), null);
        npc.setMovementRoute(nodes);
        return true;
    }

    private static String driveCapturedRoute(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        float x = ((Number) invoke(body, "getX")).floatValue();
        float y = ((Number) invoke(body, "getY")).floatValue();

        float[] node = npc.currentMovementNode();
        while (node != null && distance(x, y, node[0], node[1]) <= 0.35f) {
            npc.advanceMovementRoute();
            node = npc.currentMovementNode();
        }

        if (node == null) {
            npc.setMovementTraversalState("ARRIVED");
            clearHumanMovementIntent(body);
            return "Succeeded";
        }

        String traversal = handleRouteTransition(npc, body, node);
        npc.setMovementTraversalState(traversal);
        if (traversal.startsWith("FAILED_")) {
            clearHumanMovementIntent(body);
            return "FailedObstacle:" + traversal;
        }
        if (!"CLEAR".equals(traversal)) {
            clearHumanMovementIntent(body);
            return "Transition:" + traversal;
        }

        applyHumanMovementIntent(body, node[0], node[1]);
        return "ManualRoute";
    }

    private static String handleRouteTransition(KnoxNpc npc, Object body, float[] node)
        throws ReflectiveOperationException {
        if ((Boolean) invoke(body, "isClimbing")) {
            return "CLIMBING";
        }

        Object currentSquare = invoke(body, "getCurrentSquare");
        Object cell = invoke(body, "getCell");
        if (currentSquare == null || cell == null) {
            return "FAILED_NO_CURRENT_SQUARE";
        }

        int currentX = ((Number) invoke(currentSquare, "getX")).intValue();
        int currentY = ((Number) invoke(currentSquare, "getY")).intValue();
        int currentZ = ((Number) invoke(currentSquare, "getZ")).intValue();
        int nextX = (int) Math.floor(node[0]);
        int nextY = (int) Math.floor(node[1]);
        int nextZ = (int) Math.floor(node[2]);
        int deltaX = nextX - currentX;
        int deltaY = nextY - currentY;

        if (deltaX == 0 && deltaY == 0 && nextZ == currentZ) {
            return "CLEAR";
        }
        if (nextZ != currentZ) {
            return "FAILED_UNSUPPORTED_Z_CHANGE";
        }
        if (Math.abs(deltaX) > 1 || Math.abs(deltaY) > 1) {
            return "CLEAR";
        }

        Object nextSquare = invoke(
            cell,
            "getGridSquare",
            int.class,
            int.class,
            int.class,
            nextX,
            nextY,
            nextZ
        );
        if (nextSquare == null) {
            return "FAILED_UNLOADED_NEXT_SQUARE";
        }

        if (Math.abs(deltaX) + Math.abs(deltaY) != 1) {
            boolean blocked = (Boolean) invoke(
                currentSquare,
                "isBlockedTo",
                currentSquare.getClass(),
                nextSquare
            );
            return blocked ? "FAILED_BLOCKED_DIAGONAL" : "CLEAR";
        }

        Object door = invoke(currentSquare, "getDoorTo", currentSquare.getClass(), nextSquare);
        if (door != null) {
            boolean open = (Boolean) invoke(door, "IsOpen");
            if (open) {
                return "CLEAR";
            }
            boolean barricaded = (Boolean) invoke(door, "isBarricaded");
            if (barricaded) {
                return "FAILED_BARRICADED_DOOR";
            }
            faceObject(body, door);
            if ((Boolean) invoke(body, "shouldBeTurning")) {
                return "TURNING_TO_DOOR";
            }
            invoke(
                door,
                "ToggleDoor",
                classFor(body, "zombie.characters.IsoGameCharacter"),
                body
            );
            return (Boolean) invoke(door, "IsOpen") ? "OPENING_DOOR" : "FAILED_LOCKED_DOOR";
        }

        Object window = invoke(currentSquare, "getWindowTo", currentSquare.getClass(), nextSquare);
        if (window != null) {
            npc.useTraversalInteractionTarget(window);
            if ((Boolean) invoke(window, "isBarricaded")) {
                return "FAILED_BARRICADED_WINDOW";
            }

            String characterState = String.valueOf(invoke(body, "getCurrentStateName"));
            if (characterState.contains("OpenWindowState")) {
                return "OPENING_WINDOW";
            }
            if (characterState.contains("SmashWindowState")) {
                return "SMASHING_WINDOW";
            }

            boolean open = (Boolean) invoke(window, "IsOpen");
            boolean smashed = (Boolean) invoke(window, "isSmashed");
            boolean canClimb = (Boolean) invoke(
                window,
                "canClimbThrough",
                classFor(body, "zombie.characters.IsoGameCharacter"),
                body
            );
            faceObject(body, window);
            if ((Boolean) invoke(body, "shouldBeTurning")) {
                return "TURNING_TO_WINDOW";
            }

            if (!open && !smashed) {
                String stage = npc.getTraversalInteractionStage();
                if ("NONE".equals(stage)) {
                    invoke(
                        body,
                        "openWindow",
                        classFor(body, "zombie.iso.objects.IsoWindow"),
                        window
                    );
                    npc.setTraversalInteractionStage("OPEN_ATTEMPTED");
                    return "STARTED_WINDOW_OPEN";
                }
                if ("OPEN_ATTEMPTED".equals(stage)) {
                    invoke(
                        body,
                        "smashWindow",
                        classFor(body, "zombie.iso.objects.IsoWindow"),
                        window
                    );
                    npc.setTraversalInteractionStage("SMASH_ATTEMPTED");
                    return "STARTED_WINDOW_SMASH";
                }
                return "FAILED_WINDOW_SMASH_DID_NOT_BREAK";
            }

            if (!canClimb) {
                return "FAILED_BLOCKED_WINDOW";
            }
            invoke(
                body,
                "climbThroughWindow",
                classFor(body, "zombie.iso.objects.IsoWindow"),
                window
            );
            return "STARTED_WINDOW_CLIMB";
        }

        Object windowThumpable = invoke(
            currentSquare,
            "getWindowThumpableTo",
            currentSquare.getClass(),
            nextSquare
        );
        if (windowThumpable != null) {
            if ((Boolean) invoke(windowThumpable, "isBarricaded")) {
                return "FAILED_BARRICADED_WINDOW";
            }
            faceObject(body, windowThumpable);
            if ((Boolean) invoke(body, "shouldBeTurning")) {
                return "TURNING_TO_WINDOW";
            }
            invoke(
                body,
                "climbThroughWindow",
                classFor(body, "zombie.iso.objects.IsoThumpable"),
                windowThumpable
            );
            return "STARTED_WINDOW_CLIMB";
        }

        Object windowFrame = invoke(
            currentSquare,
            "getWindowFrameTo",
            currentSquare.getClass(),
            nextSquare
        );
        if (windowFrame != null) {
            invoke(
                body,
                "climbThroughWindowFrame",
                classFor(body, "zombie.iso.objects.IsoWindowFrame"),
                windowFrame
            );
            return "STARTED_WINDOW_FRAME_CLIMB";
        }

        Object direction = cardinalDirection(body, deltaX, deltaY);
        boolean hoppable = (Boolean) invoke(
            currentSquare,
            "isHoppableTo",
            currentSquare.getClass(),
            nextSquare
        );
        if (hoppable) {
            invoke(
                body,
                "faceDirection",
                classFor(body, "zombie.iso.IsoDirections"),
                direction
            );
            if ((Boolean) invoke(body, "shouldBeTurning")) {
                return "TURNING_TO_FENCE";
            }
            invoke(
                body,
                "climbOverFence",
                classFor(body, "zombie.iso.IsoDirections"),
                direction
            );
            return "STARTED_FENCE_CLIMB";
        }

        Object wallHoppable = invoke(
            currentSquare,
            "getWallHoppableTo",
            currentSquare.getClass(),
            nextSquare
        );
        if (wallHoppable != null) {
            boolean canClimb = (Boolean) invoke(
                body,
                "canClimbOverWall",
                classFor(body, "zombie.iso.IsoDirections"),
                direction
            );
            if (!canClimb) {
                return "FAILED_UNCLIMBABLE_WALL";
            }
            invoke(
                body,
                "climbOverWall",
                classFor(body, "zombie.iso.IsoDirections"),
                direction
            );
            return "STARTED_WALL_CLIMB";
        }

        boolean blocked = (Boolean) invoke(
            currentSquare,
            "isBlockedTo",
            currentSquare.getClass(),
            nextSquare
        );
        return blocked ? "FAILED_STATIC_BLOCKAGE" : "CLEAR";
    }

    private static void faceObject(Object body, Object object)
        throws ReflectiveOperationException {
        invoke(body, "faceThisObject", classFor(body, "zombie.iso.IsoObject"), object);
    }

    private static Object cardinalDirection(Object body, int deltaX, int deltaY)
        throws ReflectiveOperationException {
        Class<?> directionsClass = classFor(body, "zombie.iso.IsoDirections");
        String name;
        if (deltaX > 0) {
            name = "E";
        } else if (deltaX < 0) {
            name = "W";
        } else if (deltaY < 0) {
            name = "N";
        } else {
            name = "S";
        }
        return directionsClass.getField(name).get(null);
    }

    private static void applyHumanMovementIntent(Object body, float nextX, float nextY)
        throws ReflectiveOperationException {
        float x = ((Number) invoke(body, "getX")).floatValue();
        float y = ((Number) invoke(body, "getY")).floatValue();
        float deltaX = nextX - x;
        float deltaY = nextY - y;
        float length = (float) Math.sqrt(deltaX * deltaX + deltaY * deltaY);
        if (length <= 0.001f) {
            clearHumanMovementIntent(body);
            return;
        }

        float directionX = deltaX / length;
        float directionY = deltaY / length;
        Class<?> isoPlayerClass = classFor(body, ISO_PLAYER_CLASS);
        Object moveDirection = isoPlayerClass.getField("playerMoveDir").get(body);
        moveDirection.getClass().getField("x").setFloat(moveDirection, directionX);
        moveDirection.getClass().getField("y").setFloat(moveDirection, directionY);
        invoke(body, "setJustMoved", boolean.class, true);
        invoke(
            body,
            "setDirectionAngle",
            float.class,
            (float) Math.toDegrees(Math.atan2(directionY, directionX))
        );

        Object aiComponent = getAiComponent(body);
        if (aiComponent != null) {
            Object controlVars = invoke(aiComponent, "getHumanControlVars");
            if (controlVars != null) {
                // Build 42 skips normal input processing for isNpc() players. Recreate the
                // same world-to-animation control-space conversion used by IsoPlayer so its
                // NPC update can supply the movement delta later in the frame.
                float animationAngle = ((Number) invoke(body, "getAnimAngleRadians"))
                    .floatValue();
                float controlX = directionX;
                float controlY = -directionY;
                float cosine = (float) Math.cos(animationAngle);
                float sine = (float) Math.sin(animationAngle);
                float strafeX = controlX * cosine - controlY * sine;
                float strafeY = controlX * sine + controlY * cosine;
                controlVars.getClass().getField("justMoved").setBoolean(controlVars, true);
                controlVars.getClass().getField("running").setBoolean(controlVars, false);
                controlVars.getClass().getField("strafeX").setFloat(controlVars, strafeX);
                controlVars.getClass().getField("strafeY").setFloat(controlVars, strafeY);
            }
        }
    }

    private static void clearHumanMovementIntent(Object body) throws ReflectiveOperationException {
        Class<?> isoPlayerClass = classFor(body, ISO_PLAYER_CLASS);
        Object moveDirection = isoPlayerClass.getField("playerMoveDir").get(body);
        moveDirection.getClass().getField("x").setFloat(moveDirection, 0.0f);
        moveDirection.getClass().getField("y").setFloat(moveDirection, 0.0f);
        invoke(body, "setJustMoved", boolean.class, false);

        Object aiComponent = getAiComponent(body);
        if (aiComponent != null) {
            Object controlVars = invoke(aiComponent, "getHumanControlVars");
            if (controlVars != null) {
                controlVars.getClass().getField("justMoved").setBoolean(controlVars, false);
                controlVars.getClass().getField("running").setBoolean(controlVars, false);
                controlVars.getClass().getField("strafeX").setFloat(controlVars, 0.0f);
                controlVars.getClass().getField("strafeY").setFloat(controlVars, 0.0f);
            }
        }
    }

    private static Object getAiComponent(Object body) throws ReflectiveOperationException {
        Class<?> aiComponentClass = classFor(body, "zombie.characters.component.AIComponent");
        return invoke(body, "getECSComponent", Class.class, aiComponentClass);
    }

    private static float distance(float firstX, float firstY, float secondX, float secondY) {
        float deltaX = firstX - secondX;
        float deltaY = firstY - secondY;
        return (float) Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    }

    private static void applyTestMarker(Object body) throws ReflectiveOperationException {
        invoke(body, "setAlphaAndTarget", float.class, 1.0f);
        invoke(body, "setAlphaAndTarget", int.class, float.class, 0, 1.0f);
        invoke(body, "setOutlineHighlight", int.class, boolean.class, 0, true);
        invoke(
            body,
            "setOutlineHighlightCol",
            int.class,
            float.class,
            float.class,
            float.class,
            float.class,
            0,
            0.1f,
            1.0f,
            0.1f,
            1.0f
        );
        invoke(body, "setOutlineThickness", float.class, 3.0f);
        invoke(body, "setHaloNote", String.class, "KNOX NPC TEST");
    }

    private static void safelyRemove(Object body) throws ReflectiveOperationException {
        try {
            clearHumanMovementIntent(body);
        } catch (Throwable ignored) {
            // World teardown must continue even if the old input components are already gone.
        }
        Class<?> modelManagerClass = classFor(body, "zombie.core.skinnedmodel.ModelManager");
        Object modelManager = modelManagerClass.getField("instance").get(null);
        invoke(modelManager, "Remove", classFor(body, "zombie.characters.IsoGameCharacter"), body);
        invoke(body, "setMovingSquare", classFor(body, GRID_SQUARE_CLASS), null);
        invoke(body, "removeFromWorld");
    }

    private static Object[] snapshotLocalPlayers(Class<?> isoPlayerClass)
        throws ReflectiveOperationException {
        Field playersField = isoPlayerClass.getField("players");
        Object players = playersField.get(null);
        int length = Array.getLength(players);
        Object[] snapshot = new Object[length];
        for (int index = 0; index < length; index++) {
            snapshot[index] = Array.get(players, index);
        }
        return snapshot;
    }

    private static boolean sameLocalPlayers(Object[] before, Object[] after) {
        if (before.length != after.length) {
            return false;
        }
        for (int index = 0; index < before.length; index++) {
            if (before[index] != after[index]) {
                return false;
            }
        }
        return true;
    }

    private static boolean isInLocalPlayerSlots(Object body) throws ReflectiveOperationException {
        Object[] localPlayers = snapshotLocalPlayers(classFor(body, ISO_PLAYER_CLASS));
        for (Object localPlayer : localPlayers) {
            if (localPlayer == body) {
                return true;
            }
        }
        return false;
    }

    private static void requireClass(Object value, String expectedName, String label) {
        if (value == null || !expectedName.equals(value.getClass().getName())) {
            String actual = value == null ? "null" : value.getClass().getName();
            throw new IllegalArgumentException(label + " must be " + expectedName + ", got " + actual);
        }
    }

    private static Class<?> classFor(Object target, String className)
        throws ClassNotFoundException {
        return Class.forName(className, false, target.getClass().getClassLoader());
    }

    private static Object invoke(Object target, String name, Class<?> parameterType, Object argument)
        throws ReflectiveOperationException {
        Method method = target.getClass().getMethod(name, parameterType);
        return method.invoke(target, argument);
    }

    private static Object invoke(
        Object target,
        String name,
        Class<?> firstType,
        Class<?> secondType,
        Object firstArgument,
        Object secondArgument
    ) throws ReflectiveOperationException {
        Method method = target.getClass().getMethod(name, firstType, secondType);
        return method.invoke(target, firstArgument, secondArgument);
    }

    private static Object invoke(
        Object target,
        String name,
        Class<?> firstType,
        Class<?> secondType,
        Class<?> thirdType,
        Class<?> fourthType,
        Class<?> fifthType,
        Object firstArgument,
        Object secondArgument,
        Object thirdArgument,
        Object fourthArgument,
        Object fifthArgument
    ) throws ReflectiveOperationException {
        Method method = target.getClass().getMethod(
            name,
            firstType,
            secondType,
            thirdType,
            fourthType,
            fifthType
        );
        return method.invoke(
            target,
            firstArgument,
            secondArgument,
            thirdArgument,
            fourthArgument,
            fifthArgument
        );
    }

    private static Object invoke(
        Object target,
        String name,
        Class<?> firstType,
        Class<?> secondType,
        Class<?> thirdType,
        Object firstArgument,
        Object secondArgument,
        Object thirdArgument
    ) throws ReflectiveOperationException {
        Method method = target.getClass().getMethod(name, firstType, secondType, thirdType);
        return method.invoke(target, firstArgument, secondArgument, thirdArgument);
    }

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getMethod(name).invoke(target);
    }
}
