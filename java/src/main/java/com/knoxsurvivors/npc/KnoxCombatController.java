package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.agent.KnoxCombatGate;
import java.util.Map;

/** Drives one controlled melee encounter through IsoPlayer's normal attack entry point. */
final class KnoxCombatController {
    private static final int ATTACK_RETRY_TICKS = 30;
    private static final int AIM_SETTLE_TICKS = 18;
    private static final int DIRECT_STATE_FALLBACK_TICKS = 3;
    private static final int ATTACK_RECOVERY_TICKS = 24;
    private static final int MISSED_SWINGS_BEFORE_REPOSITION = 3;
    private static final float REAPPROACH_BUFFER = 0.20f;

    private KnoxNpc npc;
    private Object target;
    private String phase = "IDLE";
    private int ticks;
    private int lastAttackTick = -ATTACK_RETRY_TICKS;
    private int attackRequests;
    private float initialTargetHealth;
    private float lastTargetHealth;
    private int initialWeaponCondition;
    private float weaponMaxRange;
    private float desiredAttackRange;
    private boolean damageObserved;
    private boolean attackAnimationObserved;
    private int aimTicks;
    private boolean directStateFallbackUsed;
    private boolean obstacleTarget;
    private boolean attackCycleActive;
    private boolean liveCombat;
    private int defenseWindowUntil;
    private Object approachSquare;
    private int attacksAtLastDamage;

    String begin(KnoxNpc activeNpc, Object zombie, Object approachSquare)
        throws ReflectiveOperationException {
        return begin(activeNpc, zombie, approachSquare, true);
    }

    String beginLive(KnoxNpc activeNpc, Object zombie, Object approachSquare)
        throws ReflectiveOperationException {
        return begin(activeNpc, zombie, approachSquare, false);
    }

    String beginLockedDoor(KnoxNpc activeNpc, Object door)
        throws ReflectiveOperationException {
        if (activeNpc == null) {
            return "COMBAT_FAILED NONE_ACTIVE";
        }
        if (door == null || !inherits(door, "zombie.iso.objects.IsoDoor")) {
            return "COMBAT_FAILED NO_LOCKED_DOOR_TARGET";
        }

        reset();
        npc = activeNpc;
        target = door;
        obstacleTarget = true;
        liveCombat = false;
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
        phase = "AIMING";
        clearMovementIntent();
        String result = "COMBAT_STARTED mode=locked-door targetHealth="
            + initialTargetHealth
            + " weaponCondition="
            + initialWeaponCondition;
        KnoxAgent.writeLog("NPC combat " + result);
        return result;
    }

    private String begin(
        KnoxNpc activeNpc,
        Object zombie,
        Object approachSquare,
        boolean controlledGate
    ) throws ReflectiveOperationException {
        if (activeNpc == null) {
            return "COMBAT_FAILED NONE_ACTIVE";
        }
        if (zombie == null || !inherits(zombie, "zombie.characters.IsoZombie")) {
            return "COMBAT_FAILED INVALID_TARGET";
        }

        reset();
        npc = activeNpc;
        target = zombie;
        this.approachSquare = approachSquare;
        liveCombat = !controlledGate;
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
        // Combat always interrupts rest. Clear posture flags that can remain set for a
        // frame after a timed sit/rest action and make both zombie eligibility and melee
        // movement treat the visibly standing shell as prone.
        body.getClass().getMethod("setSitOnGround", boolean.class).invoke(body, false);
        body.getClass().getMethod("setSittingOnFurniture", boolean.class).invoke(body, false);
        body.getClass().getMethod("setOnFloor", boolean.class).invoke(body, false);
        body.getClass().getMethod("setVariable", String.class, boolean.class)
            .invoke(body, "forceGetUp", true);
        weaponMaxRange = ((Number) weapon.getClass().getMethod("getMaxRange").invoke(weapon))
            .floatValue();
        // For moving zombies, get much closer to ensure hits land even when target is chasing player.
        desiredAttackRange = Math.max(0.50f, weaponMaxRange - 0.40f);
        initialTargetHealth = health(target);
        lastTargetHealth = initialTargetHealth;

        if (controlledGate) {
            // The development gate isolates outgoing combat. Live autonomy leaves both
            // characters vulnerable and allows the zombie to keep moving and attacking.
            body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, true);
            target.getClass().getMethod("setCanWalk", boolean.class).invoke(target, false);
            target.getClass().getMethod("setUseless", boolean.class).invoke(target, true);
            target.getClass().getMethod("setTarget", classFor(target, "zombie.iso.IsoMovingObject"))
                .invoke(target, (Object) null);
        } else {
            body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, false);
            target.getClass().getMethod("setCanWalk", boolean.class).invoke(target, true);
            target.getClass().getMethod("setUseless", boolean.class).invoke(target, false);
        }

        beginLiveApproach();
        phase = "APPROACHING";
        String result = "COMBAT_STARTED mode=" + (controlledGate ? "gate" : "live")
            + " targetHealth=" + initialTargetHealth
            + " weaponCondition=" + initialWeaponCondition
            + " maxRange=" + weaponMaxRange
            + " desiredRange=" + desiredAttackRange;
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
            attacksAtLastDamage = attackRequests;
            KnoxAgent.writeLog(
                "NPC combat DAMAGE targetHealth=" + currentHealth + " previous=" + lastTargetHealth
            );
        }
        lastTargetHealth = currentHealth;

        if (targetFinished(target)) {
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
            return "COMBAT_SUCCEEDED target=" + (obstacleTarget ? "locked-door" : "zombie")
                + " attacks=" + attackRequests
                + " damageObserved=" + damageObserved
                + " targetHealth=" + currentHealth
                + " weaponCondition=" + initialWeaponCondition + "->" + condition;
        }

        Object body = npc.getBody();
        float targetX = ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue();
        float targetY = ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue();
        float bodyX = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
        float bodyY = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
        float dx = targetX - bodyX;
        float dy = targetY - bodyY;
        float targetDistance = (float) Math.sqrt(dx * dx + dy * dy);
        float reapproachThreshold = desiredAttackRange + REAPPROACH_BUFFER;

        String bodyAction = String.valueOf(
            body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
        );
        if (liveCombat && isHitReactionAction(bodyAction)) {
            // A vanilla zombie hit reaction owns the shell until its action graph exits.
            // Reapplying aim/attack input here suppresses the visible reaction and can
            // leave AttackType set, which also makes a frontal zombie collision return
            // before AddRandomDamageFromZombie is called.
            clearAttackIntent();
            body.getClass().getMethod("clearVariable", String.class)
                .invoke(body, "AttackType");
            attackCycleActive = false;
            lastAttackTick = ticks;
            defenseWindowUntil = Math.max(
                defenseWindowUntil,
                ticks + ATTACK_RECOVERY_TICKS
            );
            return "COMBAT_REACTING action=" + bodyAction
                + " targetHealth=" + currentHealth;
        }

        if ("APPROACHING".equals(phase) && !obstacleTarget) {
            if (targetDistance > reapproachThreshold) {
                // Keep one range-based destination under the captured-route adapter.
                // Replacing it with pathToCharacter() every few ticks sends the shell
                // into the target's occupied space, then repeatedly invalidates its
                // own route as the target and animation graph move.
                String movement = KnoxNpcFactory.tickMovement(npc, targetDistance, "run");
                if (movement.startsWith("Failed")) {
                    phase = "FAILED";
                    clearAttackIntent();
                    return "COMBAT_FAILED LIVE_PURSUIT " + movement;
                }
                return "COMBAT_APPROACHING movement=" + movement
                    + " liveDistance=" + targetDistance
                    + " desiredRange=" + desiredAttackRange
                    + " targetHealth=" + currentHealth;
            }
            phase = "AIMING";
            aimTicks = 0;
            clearMovementIntent();
        } else if ("APPROACHING".equals(phase)) {
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

        if (!obstacleTarget && targetDistance > reapproachThreshold) {
            boolean attackInProgress = (Boolean) body.getClass().getMethod("isAttacking").invoke(body)
                || (Boolean) body.getClass().getMethod("isPerformingAttackAnimation").invoke(body);
            if (!attackInProgress) {
                clearAttackIntent();
                beginLiveApproach();
                phase = "APPROACHING";
                aimTicks = 0;
                KnoxAgent.writeLog(
                    "NPC combat REAPPROACH distance=" + targetDistance
                        + " desiredRange=" + desiredAttackRange
                );
                return "COMBAT_REAPPROACHING distance=" + targetDistance
                    + " targetHealth=" + currentHealth;
            }
        }
        Object targetSquare = obstacleTarget
            ? target.getClass().getMethod("getSquare").invoke(target)
            : target.getClass().getMethod("getCurrentSquare").invoke(target);
        body.getClass().getMethod(
            "setAttackTargetSquare",
            classFor(body, "zombie.iso.IsoGridSquare")
        ).invoke(body, targetSquare);

        boolean attackStarted = (Boolean) body.getClass().getMethod("isAttackStarted").invoke(body);
        boolean attacking = (Boolean) body.getClass().getMethod("isAttacking").invoke(body);
        boolean attackAnimation = (Boolean) body.getClass()
            .getMethod("isPerformingAttackAnimation").invoke(body);
        boolean attackActive = attackStarted || attacking || attackAnimation;
        if (attackCycleActive && !attackActive) {
            // Yield the complete interval between swings to vanilla defense/hit
            // reactions. AttackState rejects a frontal collision while the target's
            // AttackType is non-empty, so clear the completed swing explicitly.
            lastAttackTick = ticks;
            attackCycleActive = false;
            if (liveCombat) {
                clearAttackIntent();
                body.getClass().getMethod("clearVariable", String.class)
                    .invoke(body, "AttackType");
                defenseWindowUntil = ticks + ATTACK_RECOVERY_TICKS;
                return "COMBAT_RECOVERING ticks=" + ATTACK_RECOVERY_TICKS
                    + " targetHealth=" + currentHealth;
            }
        } else {
            attackCycleActive = attackActive;
        }

        if (liveCombat && ticks < defenseWindowUntil) {
            return "COMBAT_RECOVERING ticks=" + (defenseWindowUntil - ticks)
                + " targetHealth=" + currentHealth;
        }

        boolean targetOnFloor = !obstacleTarget
            && (Boolean) target.getClass().getMethod("isOnFloor").invoke(target);
        // SwipeStatePlayer owns orientation during an active swing. Forcing a new
        // heading during that graph produces visible 360-degree turns and can move
        // the collision arc away from the attack target.
        if (!attackActive) {
            faceTarget(body, targetX, targetY);
        }

        if (liveCombat
            && attackRequests - attacksAtLastDamage >= MISSED_SWINGS_BEFORE_REPOSITION) {
            clearAttackIntent();
            KnoxNpcFactory.moveToRangeFromCurrentSide(
                npc,
                target,
                approachSquare,
                desiredAttackRange
            );
            npc.getBody().getClass().getMethod("setRunning", boolean.class).invoke(npc.getBody(), true);
            phase = "APPROACHING";
            aimTicks = 0;
            attackCycleActive = false;
            attacksAtLastDamage = attackRequests;
            KnoxAgent.writeLog(
                "NPC combat REPOSITION missedSwings=" + MISSED_SWINGS_BEFORE_REPOSITION
                    + " distance=" + targetDistance
                    + " desiredRange=" + desiredAttackRange
            );
            return "COMBAT_REPOSITIONING distance=" + targetDistance
                + " targetHealth=" + currentHealth;
        }
        applyCombatStance(body, false, targetOnFloor);

        if ("AIMING".equals(phase)) {
            aimTicks++;
            if (aimTicks < AIM_SETTLE_TICKS) {
                return "COMBAT_AIMING ticks=" + aimTicks + "/" + AIM_SETTLE_TICKS
                    + " targetHealth=" + currentHealth;
            }
            phase = "ATTACKING";
        }

        boolean weaponReady = (Boolean) body.getClass().getMethod("isWeaponReady").invoke(body);
        boolean initiateAttack = (Boolean) body.getClass().getMethod("isInitiateAttack").invoke(body);
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
        String attackType = String.valueOf(
            body.getClass().getMethod("getAttackType").invoke(body)
        );
        boolean attackTypeClear = attackType.isEmpty() || "NONE".equalsIgnoreCase(attackType);
        if (!attackStarted && !attacking && weaponReady && attackTypeClear
            && ticks - lastAttackTick >= ATTACK_RETRY_TICKS) {
            requestAttack(body, targetOnFloor);
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
            + " attackType=" + attackType;
    }

    String diagnostics() {
        if (npc == null || target == null) {
            return "COMBAT_DIAGNOSTICS phase=" + phase + " active=false";
        }
        try {
            Object body = npc.getBody();
            float dx = ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue()
                - ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
            float dy = ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue()
                - ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
            return "COMBAT_DIAGNOSTICS phase=" + phase
                + " active=true ticks=" + ticks
                + " distance=" + (float) Math.sqrt(dx * dx + dy * dy)
                + " attacks=" + attackRequests
                + " damageObserved=" + damageObserved
                + " targetHealth=" + health(target)
                + " bodyHealth=" + KnoxHealthController.health(body)
                + " bodyState=" + body.getClass().getMethod("getCurrentStateName").invoke(body)
                + " bodyAction="
                + body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
                + " attackType=" + body.getClass().getMethod("getAttackType").invoke(body);
        } catch (ReflectiveOperationException exception) {
            return "COMBAT_DIAGNOSTICS_FAILED " + exception.getClass().getSimpleName()
                + ": " + exception.getMessage();
        }
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
        weaponMaxRange = 0.0f;
        desiredAttackRange = 0.0f;
        damageObserved = false;
        attackAnimationObserved = false;
        aimTicks = 0;
        directStateFallbackUsed = false;
        obstacleTarget = false;
        attackCycleActive = false;
        liveCombat = false;
        defenseWindowUntil = 0;
        approachSquare = null;
        attacksAtLastDamage = 0;
    }

    private void beginLiveApproach() throws ReflectiveOperationException {
        if (approachSquare == null) {
            throw new IllegalStateException("Live combat has no approach square");
        }
        // The selected square establishes the side from which this survivor should
        // engage. The final point remains at weapon range from the zombie, not on
        // the zombie's current coordinate.
        KnoxNpcFactory.moveToRangeFrom(npc, target, approachSquare, desiredAttackRange);
        npc.getBody().getClass().getMethod("setRunning", boolean.class).invoke(npc.getBody(), true);
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
        body.getClass().getMethod("setAimAtFloor", boolean.class).invoke(body, false);
        body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, false);
        body.getClass().getField("isCharging").setBoolean(body, false);
        body.getClass().getField("useChargeDelta").setFloat(body, 0.0f);
        body.getClass().getMethod("clearHandToHandAttack").invoke(body);
        setAiAttackIntent(body, false, false);
    }

    private static void applyCombatStance(Object body, boolean initiate, boolean aimAtFloor)
        throws ReflectiveOperationException {
        body.getClass().getMethod("setBannedAttacking", boolean.class).invoke(body, false);
        body.getClass().getMethod("setAuthorizeMeleeAction", boolean.class).invoke(body, true);
        body.getClass().getMethod("setAuthorizeShoveStomp", boolean.class)
            .invoke(body, aimAtFloor);
        body.getClass().getMethod("setAimAtFloor", boolean.class).invoke(body, aimAtFloor);
        body.getClass().getMethod("setIsAiming", boolean.class).invoke(body, true);
        body.getClass().getField("isCharging").setBoolean(body, true);
        setAiAttackIntent(body, true, initiate);
    }

    private static void requestAttack(Object body, boolean aimAtFloor)
        throws ReflectiveOperationException {
        body.getClass().getMethod("clearHandToHandAttack").invoke(body);
        body.getClass().getMethod("setAimAtFloor", boolean.class).invoke(body, aimAtFloor);
        body.getClass().getField("useChargeDelta").setFloat(body, 36.0f);
        applyCombatStance(body, false, aimAtFloor);
        body.getClass().getMethod("pressedAttack").invoke(body);
        body.getClass().getMethod("setAttackStarted", boolean.class).invoke(body, true);
        body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, true);
        setAiAttackIntent(body, true, true);
    }

    private static boolean isHitReactionAction(String action) {
        return action != null
            && action.toLowerCase(java.util.Locale.ROOT).contains("hitreaction");
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

    private static boolean targetFinished(Object target) throws ReflectiveOperationException {
        if (inherits(target, "zombie.iso.objects.IsoDoor")) {
            return (Boolean) target.getClass().getMethod("isDestroyed").invoke(target);
        }
        return (Boolean) target.getClass().getMethod("isDead").invoke(target);
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
