package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.agent.KnoxCombatGate;
import java.util.Map;

/** Drives one controlled melee encounter through IsoPlayer's normal attack entry point. */
final class KnoxCombatController {
    private static final int ATTACK_RETRY_TICKS = 30;
    private static final int AIM_SETTLE_TICKS = 18;
    private static final int DIRECT_STATE_FALLBACK_TICKS = 3;

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
    private int aimTicks;
    private boolean directStateFallbackUsed;

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
        Class.forName(
            "zombie.ai.states.SwipeStatePlayer",
            true,
            body.getClass().getClassLoader()
        );
        if (!KnoxCombatGate.isPatchReady()) {
            reset();
            return "COMBAT_FAILED CALLBACK_PATCH_NOT_READY calls="
                + KnoxCombatGate.getPatchedCallCount();
        }
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
                clearAttackIntent();
                return "COMBAT_FAILED APPROACH " + movement;
            }
            if (!"Succeeded".equals(movement)) {
                return "COMBAT_APPROACHING movement=" + movement + " targetHealth=" + currentHealth;
            }
            phase = "AIMING";
            clearMovementIntent();
        }

        if ("FAILED".equals(phase) || "SUCCEEDED".equals(phase)) {
            return "COMBAT_" + phase;
        }

        Object body = npc.getBody();
        float targetX = ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue();
        float targetY = ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue();
        faceTarget(body, targetX, targetY);
        applyCombatStance(body, false);
        Object targetSquare = target.getClass().getMethod("getCurrentSquare").invoke(target);
        body.getClass().getMethod(
            "setAttackTargetSquare",
            classFor(body, "zombie.iso.IsoGridSquare")
        ).invoke(body, targetSquare);

        if ("AIMING".equals(phase)) {
            aimTicks++;
            if (aimTicks < AIM_SETTLE_TICKS) {
                return "COMBAT_AIMING ticks=" + aimTicks + "/" + AIM_SETTLE_TICKS
                    + " targetHealth=" + currentHealth;
            }
            phase = "ATTACKING";
        }

        boolean attackStarted = (Boolean) body.getClass().getMethod("isAttackStarted").invoke(body);
        boolean attacking = (Boolean) body.getClass().getMethod("isAttacking").invoke(body);
        boolean weaponReady = (Boolean) body.getClass().getMethod("isWeaponReady").invoke(body);
        boolean initiateAttack = (Boolean) body.getClass().getMethod("isInitiateAttack").invoke(body);
        boolean attackAnimation = (Boolean) body.getClass()
            .getMethod("isPerformingAttackAnimation").invoke(body);
        attackAnimationObserved = attackAnimationObserved || attackAnimation;
        if (attackAnimation) {
            body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, false);
            setAiAttackIntent(body, true, false);
        }
        if (attackRequests > 0 && !attackAnimationObserved && !damageObserved) {
            setAiAttackIntent(body, true, true);
            body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, true);
        }
        if (attackRequests > 0
            && !directStateFallbackUsed
            && !attackAnimationObserved
            && ticks - lastAttackTick >= DIRECT_STATE_FALLBACK_TICKS
            && "idle".equalsIgnoreCase(String.valueOf(
                body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
            ))) {
            enterSwipeState(body);
            directStateFallbackUsed = true;
            KnoxAgent.writeLog("NPC combat DIRECT_SWIPE_STATE_FALLBACK");
        }
        if (attackStarted
            && attackRequests > 0
            && ticks - lastAttackTick > 180
            && !attackAnimationObserved
            && !damageObserved) {
            phase = "FAILED";
            clearAttackIntent();
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
            requestAttack(body);
            attackRequests++;
            lastAttackTick = ticks;
            attackAnimationObserved = false;
            directStateFallbackUsed = false;
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
            + " fallback=" + directStateFallbackUsed
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
        aimTicks = 0;
        directStateFallbackUsed = false;
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
        body.getClass().getMethod("setAuthorizeShoveStomp", boolean.class).invoke(body, false);
        body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, false);
        body.getClass().getMethod("setAttackStarted", boolean.class).invoke(body, false);
        body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, false);
        body.getClass().getField("isCharging").setBoolean(body, false);
        body.getClass().getField("useChargeDelta").setFloat(body, 0.0f);
        body.getClass().getMethod("clearHandToHandAttack").invoke(body);
        setAiAttackIntent(body, false, false);
    }

    private static void applyCombatStance(Object body, boolean initiate)
        throws ReflectiveOperationException {
        body.getClass().getMethod("setBannedAttacking", boolean.class).invoke(body, false);
        body.getClass().getMethod("setAuthorizeMeleeAction", boolean.class).invoke(body, true);
        body.getClass().getMethod("setAuthorizeShoveStomp", boolean.class).invoke(body, false);
        body.getClass().getMethod("setIsAiming", boolean.class).invoke(body, true);
        body.getClass().getField("isCharging").setBoolean(body, true);
        setAiAttackIntent(body, true, initiate);
    }

    private static void requestAttack(Object body) throws ReflectiveOperationException {
        body.getClass().getMethod("clearHandToHandAttack").invoke(body);
        body.getClass().getMethod("setAimAtFloor", boolean.class).invoke(body, false);
        body.getClass().getField("useChargeDelta").setFloat(body, 36.0f);
        applyCombatStance(body, false);
        body.getClass().getMethod("pressedAttack").invoke(body);
        body.getClass().getMethod("setAttackStarted", boolean.class).invoke(body, true);
        body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, true);
        setAiAttackIntent(body, true, true);
    }

    private static void enterSwipeState(Object body) throws ReflectiveOperationException {
        ClassLoader loader = body.getClass().getClassLoader();
        Class<?> swipeClass = Class.forName("zombie.ai.states.SwipeStatePlayer", true, loader);
        Object swipeState = swipeClass.getMethod("instance").invoke(null);
        body.getClass().getMethod("changeState", classFor(body, "zombie.ai.State"))
            .invoke(body, swipeState);
        body.getClass().getMethod("setAttackStarted", boolean.class).invoke(body, true);
        body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, true);
        setAiAttackIntent(body, true, true);
    }

    private static void setAiAttackIntent(Object body, boolean aiming, boolean initiate)
        throws ReflectiveOperationException {
        Class<?> aiComponentClass = classFor(body, "zombie.characters.component.AIComponent");
        Object componentMap = body.getClass().getMethod("getECSComponentMap").invoke(body);
        Object aiComponent = ((Map<?, ?>) componentMap).get(aiComponentClass);
        if (aiComponent == null) {
            throw new IllegalStateException("NPC has no AIComponent for combat input");
        }
        Object controlVars = aiComponent.getClass().getMethod("getHumanControlVars")
            .invoke(aiComponent);
        if (controlVars == null) {
            throw new IllegalStateException("NPC has no human control variables for combat input");
        }
        controlVars.getClass().getField("aiming").setBoolean(controlVars, aiming);
        controlVars.getClass().getField("melee").setBoolean(controlVars, false);
        controlVars.getClass().getField("bannedAttacking").setBoolean(controlVars, false);
        controlVars.getClass().getField("initiateAttack").setBoolean(controlVars, initiate);
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
