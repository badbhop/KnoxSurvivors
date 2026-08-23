package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;

/** Drives one controlled melee encounter through IsoPlayer's normal attack entry point. */
final class KnoxCombatController {
    private static final int ATTACK_RETRY_TICKS = 30;

    private KnoxNpc npc;
    private Object target;
    private String phase = "IDLE";
    private int ticks;
    private int lastAttackTick = -ATTACK_RETRY_TICKS;
    private int attackRequests;
    private float initialTargetHealth;
    private float lastTargetHealth;
    private int initialWeaponCondition;
    private boolean damageObserved;
    private boolean attackAnimationObserved;

    String begin(KnoxNpc activeNpc, Object zombie, Object approachSquare)
        throws ReflectiveOperationException {
        if (activeNpc == null) {
            return "COMBAT_FAILED NONE_ACTIVE";
        }
        if (zombie == null || !inherits(zombie, "zombie.characters.IsoZombie")) {
            return "COMBAT_FAILED INVALID_TARGET";
        }

        reset();
        npc = activeNpc;
        target = zombie;
        Object body = npc.getBody();
        Object weapon = body.getClass().getMethod("getPrimaryHandItem").invoke(body);
        if (weapon == null || !inherits(weapon, "zombie.inventory.types.HandWeapon")) {
            reset();
            return "COMBAT_FAILED NO_EQUIPPED_WEAPON";
        }

        initialWeaponCondition = ((Number) weapon.getClass().getMethod("getCondition")
            .invoke(weapon)).intValue();
        initialTargetHealth = health(target);
        lastTargetHealth = initialTargetHealth;

        // This first gate isolates outgoing player combat. Incoming injury is tested later.
        body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, true);
        target.getClass().getMethod("setCanWalk", boolean.class).invoke(target, false);
        target.getClass().getMethod("setUseless", boolean.class).invoke(target, true);
        target.getClass().getMethod("setTarget", classFor(target, "zombie.iso.IsoMovingObject"))
            .invoke(target, (Object) null);

        KnoxNpcFactory.moveTo(npc, approachSquare);
        npc.clearMovementRoute();
        phase = "APPROACHING";
        String result = "COMBAT_STARTED targetHealth=" + initialTargetHealth
            + " weaponCondition=" + initialWeaponCondition;
        KnoxAgent.writeLog("NPC combat " + result);
        return result;
    }

    String tick() throws ReflectiveOperationException {
        if (npc == null || target == null) {
            return "COMBAT_IDLE";
        }

        ticks++;
        float currentHealth = health(target);
        if (currentHealth < lastTargetHealth) {
            damageObserved = true;
            KnoxAgent.writeLog(
                "NPC combat DAMAGE targetHealth=" + currentHealth + " previous=" + lastTargetHealth
            );
        }
        lastTargetHealth = currentHealth;

        if ((Boolean) target.getClass().getMethod("isDead").invoke(target)) {
            if (attackRequests == 0 || !damageObserved) {
                phase = "FAILED";
                clearAttackIntent();
                return "COMBAT_FAILED TARGET_DIED_WITHOUT_NPC_DAMAGE attacks="
                    + attackRequests + " damageObserved=" + damageObserved;
            }
            phase = "SUCCEEDED";
            clearAttackIntent();
            Object weapon = npc.getBody().getClass().getMethod("getPrimaryHandItem")
                .invoke(npc.getBody());
            int condition = weapon == null
                ? -1
                : ((Number) weapon.getClass().getMethod("getCondition").invoke(weapon)).intValue();
            return "COMBAT_SUCCEEDED attacks=" + attackRequests
                + " damageObserved=" + damageObserved
                + " targetHealth=" + currentHealth
                + " weaponCondition=" + initialWeaponCondition + "->" + condition;
        }

        if ("APPROACHING".equals(phase)) {
            String movement = KnoxNpcFactory.tickMovement(npc);
            if (movement.startsWith("Failed")) {
                phase = "FAILED";
                return "COMBAT_FAILED APPROACH " + movement;
            }
            if (!"Succeeded".equals(movement)) {
                return "COMBAT_APPROACHING movement=" + movement + " targetHealth=" + currentHealth;
            }
            phase = "ATTACKING";
            clearMovementIntent();
        }

        if ("FAILED".equals(phase) || "SUCCEEDED".equals(phase)) {
            return "COMBAT_" + phase;
        }

        Object body = npc.getBody();
        float targetX = ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue();
        float targetY = ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue();
        faceTarget(body, targetX, targetY);

        body.getClass().getMethod("setBannedAttacking", boolean.class).invoke(body, false);
        body.getClass().getMethod("setAuthorizeMeleeAction", boolean.class).invoke(body, true);
        body.getClass().getMethod("setAuthorizeShoveStomp", boolean.class).invoke(body, false);
        body.getClass().getMethod("setIsAiming", boolean.class).invoke(body, true);

        boolean attackStarted = (Boolean) body.getClass().getMethod("isAttackStarted").invoke(body);
        boolean attacking = (Boolean) body.getClass().getMethod("isAttacking").invoke(body);
        boolean weaponReady = (Boolean) body.getClass().getMethod("isWeaponReady").invoke(body);
        boolean initiateAttack = (Boolean) body.getClass().getMethod("isInitiateAttack").invoke(body);
        boolean attackAnimation = (Boolean) body.getClass()
            .getMethod("isPerformingAttackAnimation").invoke(body);
        attackAnimationObserved = attackAnimationObserved || attackAnimation;
        if (attackStarted
            && attackRequests > 0
            && ticks - lastAttackTick > 180
            && !attackAnimationObserved
            && !damageObserved) {
            phase = "FAILED";
            return "COMBAT_FAILED ATTACK_STALLED state="
                + body.getClass().getMethod("getCurrentStateName").invoke(body)
                + " action="
                + body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
                + " initiateAttack="
                + initiateAttack
                + " attackType="
                + body.getClass().getMethod("getAttackType").invoke(body);
        }
        if (!attackStarted && !attacking && weaponReady && ticks - lastAttackTick >= ATTACK_RETRY_TICKS) {
            body.getClass().getMethod("pressedAttack").invoke(body);
            attackRequests++;
            lastAttackTick = ticks;
            KnoxAgent.writeLog(
                "NPC combat ATTACK_REQUEST count=" + attackRequests + " targetHealth=" + currentHealth
            );
        }

        return "COMBAT_ATTACKING attacks=" + attackRequests
            + " attackStarted=" + attackStarted
            + " attacking=" + attacking
            + " initiateAttack=" + initiateAttack
            + " attackAnimation=" + attackAnimation
            + " animationObserved=" + attackAnimationObserved
            + " weaponReady=" + weaponReady
            + " damageObserved=" + damageObserved
            + " targetHealth=" + currentHealth
            + " state=" + body.getClass().getMethod("getCurrentStateName").invoke(body)
            + " action=" + body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
            + " attackType=" + body.getClass().getMethod("getAttackType").invoke(body);
    }

    void reset() {
        if (npc != null) {
            try {
                clearAttackIntent();
            } catch (ReflectiveOperationException ignored) {
                // World teardown may invalidate the body before the bridge is notified.
            }
        }
        npc = null;
        target = null;
        phase = "IDLE";
        ticks = 0;
        lastAttackTick = -ATTACK_RETRY_TICKS;
        attackRequests = 0;
        initialTargetHealth = 0.0f;
        lastTargetHealth = 0.0f;
        initialWeaponCondition = -1;
        damageObserved = false;
        attackAnimationObserved = false;
    }

    private void clearMovementIntent() throws ReflectiveOperationException {
        npc.clearMovementRoute();
        Object body = npc.getBody();
        Object pathfinder = body.getClass().getMethod("getPathFindBehavior2").invoke(body);
        pathfinder.getClass().getMethod("cancel").invoke(pathfinder);
    }

    private void clearAttackIntent() throws ReflectiveOperationException {
        Object body = npc.getBody();
        body.getClass().getMethod("setIsAiming", boolean.class).invoke(body, false);
        body.getClass().getMethod("setAuthorizeMeleeAction", boolean.class).invoke(body, false);
        body.getClass().getMethod("clearHandToHandAttack").invoke(body);
    }

    private static void faceTarget(Object body, float targetX, float targetY)
        throws ReflectiveOperationException {
        float x = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
        float y = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
        float directionX = targetX - x;
        float directionY = targetY - y;
        float length = (float) Math.sqrt(directionX * directionX + directionY * directionY);
        if (length <= 0.001f) {
            return;
        }
        directionX /= length;
        directionY /= length;
        body.getClass().getMethod("setTargetAndCurrentDirection", float.class, float.class)
            .invoke(body, directionX, directionY);
        body.getClass().getMethod("setForwardDirection", float.class, float.class)
            .invoke(body, directionX, directionY);
        body.getClass().getMethod("setDirectionAngle", float.class)
            .invoke(body, (float) Math.toDegrees(Math.atan2(directionY, directionX)));
    }

    private static float health(Object character) throws ReflectiveOperationException {
        return ((Number) character.getClass().getMethod("getHealth").invoke(character)).floatValue();
    }

    private static boolean inherits(Object value, String className) {
        for (Class<?> type = value.getClass(); type != null; type = type.getSuperclass()) {
            if (className.equals(type.getName())) {
                return true;
            }
        }
        return false;
    }

    private static Class<?> classFor(Object source, String className)
        throws ClassNotFoundException {
        return Class.forName(className, false, source.getClass().getClassLoader());
    }
}
