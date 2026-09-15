package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.agent.KnoxCombatGate;
import com.knoxsurvivors.agent.KnoxHumanCombatGate;
import java.util.Map;

/** Drives one controlled melee encounter through IsoPlayer's normal attack entry point. */
final class KnoxCombatController {
    private static final int ATTACK_RETRY_TICKS = 30;
    private static final int DEFAULT_AIM_SETTLE_TICKS = 18;
    private static final int MIN_AIM_SETTLE_TICKS = 8;
    private static final int MAX_AIM_SETTLE_TICKS = 30;
    private static final int DIRECT_STATE_FALLBACK_TICKS = 3;
    private static final int ATTACK_RECOVERY_TICKS = 24;
    private static final int MELEE_RECOVERY_TICKS = 30;
    private static final int MISSED_SWINGS_BEFORE_REPOSITION = 3;
    private static final float ATTACK_ENTRY_BUFFER = 0.05f;
    private static final float REAPPROACH_BUFFER = 0.20f;
    private static final int RANGED_REPOSITION_COOLDOWN_TICKS = 60;
    private static final int APPROACH_REFRESH_TICKS = 30;

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
    private boolean rangedWeapon;
    private Object combatWeapon;
    private boolean damageObserved;
    private boolean attackAnimationObserved;
    private int aimTicks;
    private int aimSettleTicks = DEFAULT_AIM_SETTLE_TICKS;
    private boolean directStateFallbackUsed;
    private boolean obstacleTarget;
    private boolean attackCycleActive;
    private boolean liveCombat;
    private int defenseWindowUntil;
    private Object approachSquare;
    private int attacksAtLastDamage;
    private int lastRangedRepositionTick = -RANGED_REPOSITION_COOLDOWN_TICKS;
    private int lastApproachTick;
    private float approachTargetX;
    private float approachTargetY;
    private int stationaryApproachRetries;

    String begin(KnoxNpc activeNpc, Object zombie, Object approachSquare)
        throws ReflectiveOperationException {
        return begin(activeNpc, zombie, approachSquare, true, DEFAULT_AIM_SETTLE_TICKS);
    }

    String beginLive(KnoxNpc activeNpc, Object target, Object approachSquare)
        throws ReflectiveOperationException {
        return begin(activeNpc, target, approachSquare, false, DEFAULT_AIM_SETTLE_TICKS);
    }

    String beginLive(
        KnoxNpc activeNpc,
        Object target,
        Object approachSquare,
        int requestedAimSettleTicks
    ) throws ReflectiveOperationException {
        return begin(activeNpc, target, approachSquare, false, requestedAimSettleTicks);
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
        combatWeapon = weapon;
        rangedWeapon = (Boolean) weapon.getClass().getMethod("isRanged").invoke(weapon);
        initialTargetHealth = health(target);
        lastTargetHealth = initialTargetHealth;

        // An interrupted prior action must not leak attack input into door combat.
        clearAttackIntent();
        npc.setCombatActive(true);
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
        Object combatTarget,
        Object approachSquare,
        boolean controlledGate,
        int requestedAimSettleTicks
    ) throws ReflectiveOperationException {
        if (activeNpc == null) {
            return "COMBAT_FAILED NONE_ACTIVE";
        }
        boolean zombieTarget = combatTarget != null
            && inherits(combatTarget, "zombie.characters.IsoZombie");
        boolean humanTarget = combatTarget != null
            && inherits(combatTarget, "zombie.characters.IsoPlayer");
        if (combatTarget == null || (!zombieTarget && (!liveTargetMode(controlledGate)
            || !humanTarget))) {
            return "COMBAT_FAILED INVALID_TARGET";
        }

        reset();
        npc = activeNpc;
        target = combatTarget;
        this.approachSquare = approachSquare;
        aimSettleTicks = clampAimSettleTicks(requestedAimSettleTicks);
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
        if (!controlledGate && zombieTarget && !KnoxCombatGate.isVisibilityPatchReady()) {
            reset();
            return "COMBAT_FAILED ZOMBIE_VISIBILITY_PATCH_NOT_READY calls="
                + KnoxCombatGate.getVisibilityPatchedCallCount();
        }
        Object weapon = body.getClass().getMethod("getPrimaryHandItem").invoke(body);
        if (weapon == null) {
            // Build 42's native player attack gate supports shove/stomp without a
            // HandWeapon. Keep the survivor in the live combat loop so an unarmed
            // NPC does not stand still until a zombie reaches them.
            initialWeaponCondition = -1;
            combatWeapon = null;
            rangedWeapon = false;
            weaponMaxRange = 1.0f;
            desiredAttackRange = 1.0f;
        } else if (inherits(weapon, "zombie.inventory.types.HandWeapon")) {
            initialWeaponCondition = ((Number) weapon.getClass().getMethod("getCondition")
                .invoke(weapon)).intValue();
            combatWeapon = weapon;
            rangedWeapon = (Boolean) weapon.getClass().getMethod("isRanged").invoke(weapon);
        } else {
            reset();
            return "COMBAT_FAILED INVALID_PRIMARY_ITEM";
        }

        // Combat always interrupts rest. Clear posture flags that can remain set for a
        // frame after a timed sit/rest action and make both zombie eligibility and melee
        // movement treat the visibly standing shell as prone.
        body.getClass().getMethod("setSitOnGround", boolean.class).invoke(body, false);
        body.getClass().getMethod("setSittingOnFurniture", boolean.class).invoke(body, false);
        body.getClass().getMethod("setOnFloor", boolean.class).invoke(body, false);
        body.getClass().getMethod("setVariable", String.class, boolean.class)
            .invoke(body, "forceGetUp", true);
        if (weapon == null) {
            weaponMaxRange = 1.0f;
            desiredAttackRange = 1.0f;
        } else {
            weaponMaxRange = ((Number) weapon.getClass().getMethod(
                "getMaxRange",
                classFor(body, "zombie.characters.IsoGameCharacter")
            ).invoke(weapon, body)).floatValue();
        }
        if (weapon == null) {
            // Native shove/stomp owns its own short attack range.
        } else if (rangedWeapon) {
            // Firearms should keep a player-like stand-off distance.  The native
            // max range already includes the survivor's aiming modifiers; use a
            // conservative middle distance so a moving zombie does not force a
            // melee collision, while still leaving room for the normal shot path.
            float minimum = 0.0f;
            try {
                minimum = ((Number) weapon.getClass().getMethod("getMinRangeRanged")
                    .invoke(weapon)).floatValue();
            } catch (ReflectiveOperationException ignored) {
                // Older compatible weapon classes may not expose this accessor.
            }
            desiredAttackRange = desiredRange(true, weaponMaxRange, minimum);
        } else {
            // Build 42's IsoGameCharacter.isMeleeAttackRange() multiplies the
            // character-adjusted maximum by the weapon's range modifier. Mirror
            // that native gate when choosing the approach point; raw script range
            // can otherwise disagree with the collision calculation.
            float rangeModifier = ((Number) weapon.getClass().getMethod(
                "getRangeMod",
                classFor(body, "zombie.characters.IsoGameCharacter")
            ).invoke(weapon, body)).floatValue();
            weaponMaxRange *= rangeModifier;
            desiredAttackRange = desiredRange(false, weaponMaxRange, 0.0f);
        }
        initialTargetHealth = health(target);
        lastTargetHealth = initialTargetHealth;

        // Build 42's standing-zombie collision callback rejects a frontal bite while
        // the target still advertises an AttackType. A previous interrupted swing can
        // leave that animation variable behind even after the boolean attack flags are
        // clear, so every new combat owner begins from one clean native input state.
        clearAttackIntent();

        if (controlledGate) {
            // The development gate isolates outgoing combat. Live autonomy leaves both
            // characters vulnerable and allows the zombie to keep moving and attacking.
            body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, true);
            target.getClass().getMethod("setCanWalk", boolean.class).invoke(target, false);
            target.getClass().getMethod("setUseless", boolean.class).invoke(target, true);
            target.getClass().getMethod("setTarget", classFor(target, "zombie.iso.IsoMovingObject"))
                .invoke(target, (Object) null);
        } else if (zombieTarget) {
            body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, false);
            target.getClass().getMethod("setCanWalk", boolean.class).invoke(target, true);
            target.getClass().getMethod("setUseless", boolean.class).invoke(target, false);
        }
        // Human targeting must not change either participant's player safety settings.
        // Native checkPVP uses coopPVP in single-player; factionPvp is not an NPC bypass.

        npc.setCombatActive(true);
        body.getClass().getMethod("setSneaking", boolean.class).invoke(body, false);
        beginLiveApproach();
        if (humanTarget) KnoxHumanCombatGate.refresh(this, body, target);
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
        if (liveCombat && inherits(target, "zombie.characters.IsoPlayer"))
            KnoxHumanCombatGate.refresh(this, npc.getBody(), target);
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
                return finish("COMBAT_FAILED TARGET_DIED_WITHOUT_NPC_DAMAGE attacks="
                    + attackRequests + " damageObserved=" + damageObserved);
            }
            phase = "SUCCEEDED";
            Object weapon = npc.getBody().getClass().getMethod("getPrimaryHandItem")
                .invoke(npc.getBody());
            int condition = weapon == null
                ? -1
                : ((Number) weapon.getClass().getMethod("getCondition").invoke(weapon)).intValue();
            return finish("COMBAT_SUCCEEDED target="
                + (obstacleTarget ? "locked-door"
                    : inherits(target, "zombie.characters.IsoPlayer") ? "human" : "zombie")
                + " attacks=" + attackRequests
                + " damageObserved=" + damageObserved
                + " targetHealth=" + currentHealth
                + " weaponCondition=" + initialWeaponCondition + "->" + condition);
        }

        if (combatantUnavailable(npc.getBody()) || targetUnavailable(target)) {
            phase = "FAILED";
            return finish("COMBAT_FAILED INVALID_OR_UNLOADED_COMBATANT");
        }

        Object body = npc.getBody();
        Object equippedWeapon = body.getClass().getMethod("getPrimaryHandItem").invoke(body);
        if (equippedWeapon != combatWeapon) {
            phase = "FAILED";
            return finish("COMBAT_FAILED WEAPON_CHANGED");
        }
        float targetX = ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue();
        float targetY = ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue();
        float bodyX = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
        float bodyY = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
        float dx = targetX - bodyX;
        float dy = targetY - bodyY;
        float targetDistance = (float) Math.sqrt(dx * dx + dy * dy);
        float attackEntryThreshold = attackEntryThreshold(desiredAttackRange);
        float reapproachThreshold = reapproachThreshold(desiredAttackRange);

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

        boolean attackInProgress = (Boolean) body.getClass().getMethod("isAttacking").invoke(body)
            || (Boolean) body.getClass().getMethod("isPerformingAttackAnimation").invoke(body);
        float minimumRangedDistance = minimumRangedDistance(desiredAttackRange);
        if (shouldRepositionRanged(
            rangedWeapon,
            targetDistance,
            minimumRangedDistance,
            ticks,
            lastRangedRepositionTick,
            attackInProgress
        )) {
            clearAttackIntent();
            KnoxNpcFactory.moveToRangeFromCurrentSide(
                npc,
                target,
                approachSquare,
                desiredAttackRange
            );
            body.getClass().getMethod("setRunning", boolean.class).invoke(body, true);
            phase = "RANGED_REPOSITIONING";
            aimTicks = 0;
            attackCycleActive = false;
            lastRangedRepositionTick = ticks;
            KnoxAgent.writeLog(
                "NPC combat RANGED_REPOSITION distance=" + targetDistance
                    + " minimum=" + minimumRangedDistance
                    + " desiredRange=" + desiredAttackRange
            );
            return "COMBAT_RANGED_REPOSITIONING distance=" + targetDistance
                + " targetHealth=" + currentHealth;
        }

        if ("RANGED_REPOSITIONING".equals(phase)) {
            // The Build 42 Lua firearm hook observes the shell's aiming/attack
            // variables independently of this controller phase. Clear them on
            // every reposition tick, not just when entering the phase, so a
            // queued attack cannot emit a shot while the survivor is running.
            clearAttackIntent();
            String movement = KnoxNpcFactory.tickMovement(npc, targetDistance, "run");
            if (movement.startsWith("Failed")) {
                phase = "FAILED";
                return finish("COMBAT_FIREARM_FALLBACK CLOSE_REPOSITION " + movement);
            }
            float resumeDistance = Math.max(minimumRangedDistance, desiredAttackRange * 0.65f);
            if (!"Succeeded".equals(movement) && targetDistance < resumeDistance) {
                return "COMBAT_RANGED_REPOSITIONING movement=" + movement
                    + " distance=" + targetDistance
                    + " resumeDistance=" + resumeDistance
                    + " targetHealth=" + currentHealth;
            }
            clearMovementIntent();
            body.getClass().getMethod("setRunning", boolean.class).invoke(body, false);
            phase = "AIMING";
            aimTicks = 0;
        } else if ("APPROACHING".equals(phase) && !obstacleTarget) {
            if (targetDistance > attackEntryThreshold) {
                // Keep one range-based destination under the captured-route adapter.
                // Replacing it with pathToCharacter() every few ticks sends the shell
                // into the target's occupied space, then repeatedly invalidates its
                // own route as the target and animation graph move.
                String movement = KnoxNpcFactory.tickMovement(npc, targetDistance, "run");
                if (movement.startsWith("Failed")) {
                    phase = "FAILED";
                    return finish("COMBAT_FAILED LIVE_PURSUIT " + movement);
                }
                boolean targetMoved = targetMovedSinceApproach(
                    targetX, targetY, approachTargetX, approachTargetY
                );
                if (shouldRefreshApproach(movement, targetMoved, ticks - lastApproachTick)) {
                    stationaryApproachRetries = targetMoved ? 0 : stationaryApproachRetries + 1;
                    if (stationaryApproachRetries > 2) {
                        return finish("COMBAT_FAILED APPROACH_OUT_OF_RANGE distance="
                            + targetDistance + " entryRange=" + attackEntryThreshold);
                    }
                    clearMovementIntent();
                    KnoxNpcFactory.moveToRangeFromCurrentSide(
                        npc, target, approachSquare, desiredAttackRange
                    );
                    rememberApproachTarget(targetX, targetY);
                    return "COMBAT_APPROACH_REFRESH targetMoved=" + targetMoved
                        + " distance=" + targetDistance;
                }
                return "COMBAT_APPROACHING movement=" + movement
                    + " liveDistance=" + targetDistance
                    + " desiredRange=" + desiredAttackRange
                    + " targetHealth=" + currentHealth;
            }
            phase = "AIMING";
            aimTicks = 0;
            clearMovementIntent();
            stationaryApproachRetries = 0;
        } else if ("APPROACHING".equals(phase)) {
            String movement = KnoxNpcFactory.tickMovement(npc);
            if (movement.startsWith("Failed")) {
                phase = "FAILED";
                return finish("COMBAT_FAILED APPROACH " + movement);
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
                defenseWindowUntil = ticks + recoveryTicks(rangedWeapon);
                return "COMBAT_RECOVERING ticks=" + recoveryTicks(rangedWeapon)
                    + " targetHealth=" + currentHealth;
            }
        } else {
            attackCycleActive = attackActive;
        }

        if (liveCombat && ticks < defenseWindowUntil) {
            // Aiming is not attacking: keep the native ready posture, but leave
            // AttackType and attack triggers cleared for normal bite/reaction gates.
            applyReadyPosture(body);
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
            rememberApproachTarget(targetX, targetY);
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
        boolean aimAtFloor = targetOnFloor;
        applyCombatStance(body, false, aimAtFloor, rangedWeapon);

        if ("AIMING".equals(phase)) {
            aimTicks++;
            if (aimTicks < aimSettleTicks) {
                return "COMBAT_AIMING ticks=" + aimTicks + "/" + aimSettleTicks
                    + " targetHealth=" + currentHealth;
            }
            phase = "ATTACKING";
        }

        boolean weaponReady = combatWeapon == null
            || (Boolean) body.getClass().getMethod("isWeaponReady").invoke(body);
        boolean initiateAttack = (Boolean) body.getClass().getMethod("isInitiateAttack").invoke(body);
        attackAnimationObserved = attackAnimationObserved || attackAnimation;
        if (attackAnimation && !rangedWeapon) {
            body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, false);
            setAiAttackIntent(body, true, false);
        }
        if (!rangedWeapon && attackRequests > 0 && !attackAnimationObserved && !damageObserved) {
            setAiAttackIntent(body, true, true);
            body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, true);
        }
        if (allowsDirectSwipeFallback(rangedWeapon)
            && attackRequests > 0
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
            return finish("COMBAT_FAILED ATTACK_STALLED state="
                + body.getClass().getMethod("getCurrentStateName").invoke(body)
                + " action="
                + body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
                + " initiateAttack="
                + initiateAttack
                + " attackType="
                + body.getClass().getMethod("getAttackType").invoke(body));
        }
        String attackType = String.valueOf(
            body.getClass().getMethod("getAttackType").invoke(body)
        );
        boolean attackTypeClear = attackType.isEmpty() || "NONE".equalsIgnoreCase(attackType);
        if (!attackStarted && !attacking && weaponReady && attackTypeClear
            && ticks - lastAttackTick >= ATTACK_RETRY_TICKS) {
            requestAttack(body, aimAtFloor, rangedWeapon);
            attackRequests++;
            lastAttackTick = ticks;
            attackAnimationObserved = false;
            directStateFallbackUsed = false;
            KnoxAgent.writeLog(
                "NPC combat ATTACK_REQUEST count=" + attackRequests + " targetHealth=" + currentHealth
            );
            if (rangedWeapon) {
                return "COMBAT_FIREARM_REQUEST attacks=" + attackRequests
                    + " targetHealth=" + currentHealth;
            }
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
                + " ranged=" + rangedWeapon
                + " aim=" + aimTicks + "/" + aimSettleTicks
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
        KnoxHumanCombatGate.clear(this);
        if (npc != null) {
            npc.setCombatActive(false);
            try {
                clearAttackIntent();
            } catch (ReflectiveOperationException ignored) {
                // World teardown may invalidate the body before the bridge is notified.
            }
            try {
                clearMovementIntent();
            } catch (ReflectiveOperationException ignored) {
                // Attempt both cleanup halves independently during world teardown.
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
        rangedWeapon = false;
        combatWeapon = null;
        damageObserved = false;
        attackAnimationObserved = false;
        aimTicks = 0;
        aimSettleTicks = DEFAULT_AIM_SETTLE_TICKS;
        directStateFallbackUsed = false;
        obstacleTarget = false;
        attackCycleActive = false;
        liveCombat = false;
        defenseWindowUntil = 0;
        approachSquare = null;
        lastApproachTick = 0;
        approachTargetX = 0.0f;
        approachTargetY = 0.0f;
        stationaryApproachRetries = 0;
        attacksAtLastDamage = 0;
        lastRangedRepositionTick = -RANGED_REPOSITION_COOLDOWN_TICKS;
    }

    private void beginLiveApproach() throws ReflectiveOperationException {
        if (approachSquare == null) {
            throw new IllegalStateException("Live combat has no approach square");
        }
        // The selected square establishes the side from which this survivor should
        // engage. The final point remains at weapon range from the zombie, not on
        // the zombie's current coordinate.
        KnoxNpcFactory.moveToRangeFrom(npc, target, approachSquare, desiredAttackRange);
        rememberApproachTarget(
            ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue(),
            ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue()
        );
        npc.getBody().getClass().getMethod("setRunning", boolean.class).invoke(npc.getBody(), true);
    }

    private void rememberApproachTarget(float x, float y) {
        approachTargetX = x;
        approachTargetY = y;
        lastApproachTick = ticks;
    }

    static boolean targetMovedSinceApproach(float x, float y, float oldX, float oldY) {
        float dx = x - oldX;
        float dy = y - oldY;
        return dx * dx + dy * dy >= 0.75f * 0.75f;
    }

    static boolean shouldRefreshApproach(String movement, boolean targetMoved, int elapsedTicks) {
        return elapsedTicks >= APPROACH_REFRESH_TICKS
            && ("Succeeded".equals(movement)
                || (targetMoved && "ManualRoute".equals(movement)));
    }

    static int clampAimSettleTicks(int requested) {
        return Math.max(MIN_AIM_SETTLE_TICKS, Math.min(MAX_AIM_SETTLE_TICKS, requested));
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
        body.getClass().getMethod("clearVariable", String.class).invoke(body, "AttackType");
        body.getClass().getMethod(
            "setAttackTargetSquare",
            classFor(body, "zombie.iso.IsoGridSquare")
        ).invoke(body, (Object) null);
        setAiAttackIntent(body, false, false);
    }

    private String finish(String result) {
        reset();
        return result;
    }

    private static boolean combatantUnavailable(Object body)
        throws ReflectiveOperationException {
        return unavailable(
            (Boolean) body.getClass().getMethod("isDead").invoke(body),
            body.getClass().getMethod("getCurrentSquare").invoke(body) == null
        );
    }

    private static boolean targetUnavailable(Object combatTarget)
        throws ReflectiveOperationException {
        return !inherits(combatTarget, "zombie.iso.objects.IsoDoor")
            && unavailable(
                false,
                combatTarget.getClass().getMethod("getCurrentSquare").invoke(combatTarget) == null
            );
    }

    static int recoveryTicks(boolean ranged) {
        return ranged ? ATTACK_RECOVERY_TICKS : MELEE_RECOVERY_TICKS;
    }

    static boolean unavailable(boolean dead, boolean missingSquare) {
        return dead || missingSquare;
    }

    static float desiredRange(boolean ranged, float maximumRange, float minimumRange) {
        if (!ranged) {
            return Math.max(0.50f, maximumRange - 0.40f);
        }
        float cappedMaximum = Math.max(1.0f, maximumRange);
        float preferred = Math.max(6.0f, cappedMaximum * 0.65f);
        return Math.min(cappedMaximum, Math.max(minimumRange + 1.0f, preferred));
    }

    static float attackEntryThreshold(float desiredRange) {
        return desiredRange + ATTACK_ENTRY_BUFFER;
    }

    static float reapproachThreshold(float desiredRange) {
        return desiredRange + REAPPROACH_BUFFER;
    }

    static float minimumRangedDistance(float desiredRange) {
        return Math.max(2.25f, Math.min(3.50f, desiredRange * 0.45f));
    }

    static boolean shouldRepositionRanged(
        boolean ranged,
        float distance,
        float minimumDistance,
        int ticks,
        int lastRepositionTick,
        boolean attackInProgress
    ) {
        return ranged
            && !attackInProgress
            && distance < minimumDistance
            && ticks - lastRepositionTick >= RANGED_REPOSITION_COOLDOWN_TICKS;
    }

    static boolean allowsDirectSwipeFallback(boolean ranged) {
        return !ranged;
    }

    static boolean liveTargetMode(boolean controlledGate) {
        return !controlledGate;
    }

    private static void applyReadyPosture(Object body) throws ReflectiveOperationException {
        body.getClass().getMethod("setIsAiming", boolean.class).invoke(body, true);
        setAiAttackIntent(body, true, false);
    }

    private static void applyCombatStance(
        Object body,
        boolean initiate,
        boolean aimAtFloor,
        boolean ranged
    )
        throws ReflectiveOperationException {
        body.getClass().getMethod("setBannedAttacking", boolean.class).invoke(body, false);
        // Despite its legacy name this is Build 42's general player attack gate.
        // ISReloadWeaponAction.attackHook rejects ranged fire when it is false.
        body.getClass().getMethod("setAuthorizeMeleeAction", boolean.class).invoke(body, true);
        body.getClass().getMethod("setAuthorizeShoveStomp", boolean.class)
            // Shove is a standing hand-to-hand action too.  Gating it on
            // aimAtFloor left an unarmed survivor unable to push an upright
            // zombie and made the native combat loop look idle until death.
            .invoke(body, !ranged);
        body.getClass().getMethod("setAimAtFloor", boolean.class).invoke(body, aimAtFloor);
        body.getClass().getMethod("setIsAiming", boolean.class).invoke(body, true);
        body.getClass().getField("isCharging").setBoolean(body, true);
        setAiAttackIntent(body, true, initiate);
    }

    private static void requestAttack(Object body, boolean aimAtFloor, boolean ranged)
        throws ReflectiveOperationException {
        body.getClass().getMethod("clearHandToHandAttack").invoke(body);
        body.getClass().getMethod("setAimAtFloor", boolean.class).invoke(body, aimAtFloor);
        body.getClass().getField("useChargeDelta").setFloat(body, 36.0f);
        applyCombatStance(body, false, aimAtFloor, ranged);
        if (!ranged) {
            body.getClass().getMethod("pressedAttack").invoke(body);
            body.getClass().getMethod("setAttackStarted", boolean.class).invoke(body, true);
            body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, true);
            setAiAttackIntent(body, true, true);
        }
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
