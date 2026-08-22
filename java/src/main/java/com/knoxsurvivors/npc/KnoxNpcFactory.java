package com.knoxsurvivors.npc;

import java.lang.reflect.Array;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

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

        Constructor<?> constructor = isoPlayerClass.getConstructor(
            isoCellClass,
            survivorDescClass,
            int.class,
            int.class,
            int.class,
            boolean.class
        );
        Object body = constructor.newInstance(cell, descriptor, x, y, z, false);

        isoPlayerClass.getMethod("setNpc", boolean.class).invoke(body, true);
        isoPlayerClass.getField("remote").setBoolean(body, true);
        isoPlayerClass.getField("playerIndex").setInt(body, -1);
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
        invoke(body, "setHaloNote", String.class, "KNOX NPC TEST");

        if (!sameLocalPlayers(localPlayersBefore, snapshotLocalPlayers(isoPlayerClass))) {
            safelyRemove(body);
            throw new IllegalStateException("IsoPlayer local-player slots changed during NPC creation");
        }

        return new KnoxNpc(id, body, x, y, z);
    }

    static void remove(KnoxNpc npc) throws ReflectiveOperationException {
        safelyRemove(npc.getBody());
    }

    static String describeLive(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
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
        return "ACTIVE "
            + npc.describe()
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
            + alpha;
    }

    private static void safelyRemove(Object body) throws ReflectiveOperationException {
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

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getMethod(name).invoke(target);
    }
}
