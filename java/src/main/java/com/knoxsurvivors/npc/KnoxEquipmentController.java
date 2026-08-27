package com.knoxsurvivors.npc;

import java.lang.reflect.Method;
import java.util.Collection;

/** Chooses equipment from items the survivor actually carries. */
final class KnoxEquipmentController {
    private KnoxEquipmentController() {
    }

    static String equipBestMelee(Object body) throws ReflectiveOperationException {
        Object inventory = invoke(body, "getInventory");
        Object best = null;
        float bestScore = Float.NEGATIVE_INFINITY;
        for (Object weapon : (Collection<?>) invoke(inventory, "getItems")) {
            if (!inherits(weapon, "zombie.inventory.types.HandWeapon")
                || (Boolean) invoke(weapon, "isRanged")
                || (Boolean) invoke(weapon, "isBroken")) {
                continue;
            }
            int conditionMax = ((Number) invoke(weapon, "getConditionMax")).intValue();
            float condition = conditionMax <= 0
                ? 0.0f
                : ((Number) invoke(weapon, "getCondition")).floatValue() / conditionMax;
            float averageDamage = (
                ((Number) invoke(weapon, "getMinDamage")).floatValue()
                    + ((Number) invoke(weapon, "getMaxDamage")).floatValue()
            ) * 0.5f;
            float score = averageDamage * 10.0f
                + condition * 5.0f
                + ((Number) invoke(weapon, "getMaxRange")).floatValue()
                + ((Number) invoke(weapon, "getBaseSpeed")).floatValue()
                + ((Number) invoke(weapon, "getCriticalChance")).floatValue() * 0.02f;
            if (score > bestScore) {
                best = weapon;
                bestScore = score;
            }
        }

        if (best == null) {
            invokeCompatible(body, "setPrimaryHandItem", (Object) null);
            invokeCompatible(body, "setSecondaryHandItem", (Object) null);
            return "NO_MELEE_WEAPON";
        }

        invokeCompatible(body, "setPrimaryHandItem", best);
        invokeCompatible(
            body,
            "setSecondaryHandItem",
            (Boolean) invoke(best, "isTwoHandWeapon") ? best : null
        );
        invoke(body, "resetModelNextFrame");
        return "EQUIPPED " + invoke(best, "getFullType") + " score=" + bestScore;
    }

    /**
     * Equips one already-owned weapon chosen by the Lua action planner.
     *
     * Firearm readiness is intentionally decided on the Lua side because Build 42's
     * native reload actions own magazines, chambers, and timed animation state.  This
     * method only performs the safe, inventory-backed hand transition; it never creates
     * ammunition or changes firearm fields directly.
     */
    static String equipOwnedWeapon(Object body, String fullType) throws ReflectiveOperationException {
        if (fullType == null || fullType.isBlank()) {
            return "EQUIP_FAILED INVALID_WEAPON";
        }
        Object inventory = invoke(body, "getInventory");
        Object selected = null;
        for (Object item : (Collection<?>) invoke(inventory, "getItems")) {
            if (!inherits(item, "zombie.inventory.types.HandWeapon")
                || (Boolean) invoke(item, "isBroken")
                || !fullType.equals(String.valueOf(invoke(item, "getFullType")))) {
                continue;
            }
            selected = item;
            break;
        }
        if (selected == null) {
            return "EQUIP_FAILED NOT_OWNED " + fullType;
        }
        invokeCompatible(body, "setPrimaryHandItem", selected);
        invokeCompatible(
            body,
            "setSecondaryHandItem",
            (Boolean) invoke(selected, "isTwoHandWeapon") ? selected : null
        );
        invoke(body, "resetModelNextFrame");
        return "EQUIPPED_WEAPON " + fullType
            + " ranged=" + invoke(selected, "isRanged");
    }

    private static boolean inherits(Object value, String className) {
        Class<?> current = value.getClass();
        while (current != null) {
            if (current.getName().equals(className)) {
                return true;
            }
            current = current.getSuperclass();
        }
        return false;
    }

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getMethod(name).invoke(target);
    }

    private static Object invokeCompatible(Object target, String name, Object argument)
        throws ReflectiveOperationException {
        for (Method method : target.getClass().getMethods()) {
            if (method.getName().equals(name) && method.getParameterCount() == 1) {
                Class<?> parameterType = method.getParameterTypes()[0];
                if (argument == null || parameterType.isInstance(argument)) {
                    return method.invoke(target, argument);
                }
            }
        }
        throw new NoSuchMethodException(target.getClass().getName() + "." + name);
    }
}
