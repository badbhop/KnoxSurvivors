package com.knoxsurvivors.npc;

import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Collection;

/** Reads and prepares the engine-owned health state used by Knox survivor bodies. */
final class KnoxHealthController {
    private static final float FULL_PART_HEALTH = 99.999f;
    private static final float VANILLA_BITE_COLLISION_RANGE = 1.0f;
    private static final float STANDING_ATTACK_VECTOR_RANGE = 0.70f;
    private static final float MINIMUM_ATTACK_SEEN_TIME = 0.55f;
    private static final float ATTACK_VISIBILITY_ENVELOPE = 1.25f;

    private KnoxHealthController() {
    }

    static float health(Object body) throws ReflectiveOperationException {
        Object damage = body.getClass().getMethod("getBodyDamage").invoke(body);
        return ((Number) damage.getClass().getMethod("getHealth").invoke(damage)).floatValue();
    }

    static int bleedingParts(Object body) throws ReflectiveOperationException {
        Object damage = body.getClass().getMethod("getBodyDamage").invoke(body);
        return ((Number) damage.getClass().getMethod("getNumPartsBleeding").invoke(damage))
            .intValue();
    }

    static int injuredParts(Object body) throws ReflectiveOperationException {
        Object damage = body.getClass().getMethod("getBodyDamage").invoke(body);
        Object bodyParts = damage.getClass().getMethod("getBodyParts").invoke(damage);
        int count = 0;
        for (Object part : (Collection<?>) bodyParts) {
            float partHealth = ((Number) part.getClass().getMethod("getHealth").invoke(part))
                .floatValue();
            if (partHealth < FULL_PART_HEALTH) {
                count++;
            }
        }
        return count;
    }

    static String status(Object body) throws ReflectiveOperationException {
        return "health=" + health(body)
            + " injuredParts=" + injuredParts(body)
            + " bleedingParts=" + bleedingParts(body);
    }

    static String prepareControlledAttack(Object body) throws ReflectiveOperationException {
        Object damage = body.getClass().getMethod("getBodyDamage").invoke(body);
        damage.getClass().getMethod("RestoreToFullHealth").invoke(damage);
        body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, false);
        return "HEALTH_GATE_READY " + status(body) + " zombieVulnerable=true";
    }

    static String normalizeToTreatableScratch(Object body) throws ReflectiveOperationException {
        Object damage = body.getClass().getMethod("getBodyDamage").invoke(body);
        damage.getClass().getMethod("RestoreToFullHealth").invoke(damage);

        Class<?> typeClass = Class.forName(
            "zombie.characters.BodyDamage.BodyPartType",
            false,
            body.getClass().getClassLoader()
        );
        @SuppressWarnings({"rawtypes", "unchecked"})
        Object forearmLeft = Enum.valueOf((Class<? extends Enum>) typeClass, "ForeArm_L");
        Object part = damage.getClass().getMethod("getBodyPart", typeClass)
            .invoke(damage, forearmLeft);
        part.getClass().getMethod("setScratched", boolean.class, boolean.class)
            .invoke(part, true, false);
        part.getClass().getMethod("SetHealth", float.class).invoke(part, 85.0f);
        part.getClass().getMethod("setBleeding", boolean.class).invoke(part, true);
        part.getClass().getMethod("setBleedingTime", float.class).invoke(part, 20.0f);
        damage.getClass().getMethod("calculateOverallHealth").invoke(damage);
        body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, true);
        String presentation = KnoxHealthPresentation.refresh(body);
        return "CONTROLLED_INJURY injury=ForeArm_L wound=scratch "
            + status(body)
            + " zombieVulnerable=false "
            + presentation;
    }

    static String refreshPresentation(Object body) throws ReflectiveOperationException {
        return KnoxHealthPresentation.refresh(body);
    }

    static String directZombieAt(Object zombie, Object body) throws ReflectiveOperationException {
        String stage = "load-classes";
        try {
        Class<?> movingObjectClass = Class.forName(
            "zombie.iso.IsoMovingObject",
            false,
            body.getClass().getClassLoader()
        );
        Class<?> gameCharacterClass = Class.forName(
            "zombie.characters.IsoGameCharacter",
            false,
            body.getClass().getClassLoader()
        );
        stage = "read-current-target";
        Object currentTarget = zombie.getClass().getMethod("getTarget").invoke(zombie);
        if (currentTarget == body) {
            stage = "refresh-current-target-vector";
            float targetDistance = refreshZombieTargetVector(zombie, body);
            stage = "restore-current-target";
            zombie.getClass().getMethod("setTarget", movingObjectClass).invoke(zombie, body);
            if (targetDistance <= ATTACK_VISIBILITY_ENVELOPE) {
                stage = "supply-current-target-visibility";
                supplyOffSlotAttackVisibility(zombie, body);
            }
            stage = "read-current-target-action";
            String currentAction = String.valueOf(
                zombie.getClass().getMethod("getCurrentActionContextStateName").invoke(zombie)
            );
            stage = "read-current-target-attacking";
            boolean attacking = (Boolean) zombie.getClass()
                .getMethod("isZombieAttacking", movingObjectClass)
                .invoke(zombie, body);
            if (attacking || "attack".equalsIgnoreCase(currentAction)) {
                return "ZOMBIE_DIRECTED status=attacking distance=" + targetDistance
                    + " " + zombieAttackDiagnostics(zombie, body);
            }
            if (!canEnterAttackFrom(currentAction)) {
                // Do not replace hit reactions, falls, climbs, or get-up actions. The
                // previous bridge could force the action graph from hitreaction straight
                // into attack, leaving the zombie in an invalid half-recovered loop.
                return "ZOMBIE_DIRECTED status=attack-deferred distance=" + targetDistance
                    + " action=" + currentAction
                    + " " + zombieAttackDiagnostics(zombie, body);
            }
            if (targetDistance <= VANILLA_BITE_COLLISION_RANGE) {
                // The off-slot IsoPlayer shell and its opponent can stop slightly farther
                // apart than the 0.72 perception-vector threshold used by bAttack. The
                // vanilla AttackState collision event accepts a real DistTo() of 1.0.
                // Clamp only the perception vector inside that same collision envelope;
                // every other getShouldAttack() guard remains authoritative.
                stage = "clamp-current-target-vector";
                clampZombieAttackVector(zombie, STANDING_ATTACK_VECTOR_RANGE);
            }
            stage = "check-current-target-attack";
            if (vanillaShouldAttack(zombie)) {
                stage = "read-current-target-seen-time";
                float targetSeenTime = ((Number) zombie.getClass()
                    .getMethod("getTargetSeenTime").invoke(zombie)).floatValue();
                // Zombie_Bite_Start is gated by targetSeenTime > 0.5. Resetting this
                // value on every perception refresh made the action state valid in
                // Java while leaving the animator with no eligible start node.
                if (targetSeenTime < MINIMUM_ATTACK_SEEN_TIME) {
                    return "ZOMBIE_DIRECTED status=attack-windup distance=" + targetDistance
                        + " " + zombieAttackDiagnostics(zombie, body);
                }
                // bAttack is a callback to IsoZombie.getShouldAttack(). With the
                // shell's isolated visibility bit held through the next engine update,
                // the normal action transition and legacy AttackState now enter in
                // their vanilla order. Forcing either state here races the animation
                // graph and repeatedly skips AttackCollisionCheck.
                return "ZOMBIE_DIRECTED status=attack-ready distance=" + targetDistance
                    + " action=" + currentAction
                    + " " + zombieAttackDiagnostics(zombie, body);
            }
            // updateLOS is intentionally disabled on off-slot shells because it writes
            // into local-player lighting. Keep pursuing until vanilla getShouldAttack()
            // passes; its standing-zombie distance limit is 0.72 tiles.
            stage = "spot-current-target";
            zombie.getClass().getMethod("spotted", movingObjectClass, boolean.class)
                .invoke(zombie, body, true);
            stage = "reassert-current-target";
            zombie.getClass().getMethod("setTarget", movingObjectClass).invoke(zombie, body);
            stage = "path-current-target";
            zombie.getClass().getMethod("pathToCharacter", gameCharacterClass)
                .invoke(zombie, body);
            if (targetDistance <= VANILLA_BITE_COLLISION_RANGE) {
                return "ZOMBIE_DIRECTED status=blocked-close distance=" + targetDistance
                    + " targetOnFloor="
                    + body.getClass().getMethod("isOnFloor").invoke(body)
                    + " targetGhost="
                    + body.getClass().getMethod("isGhostMode").invoke(body)
                    + " targetProtected="
                    + body.getClass().getMethod("isZombiesDontAttack").invoke(body)
                    + " zombieState="
                    + zombie.getClass().getMethod("getCurrentStateName").invoke(zombie)
                    + " zombieAction="
                    + zombie.getClass().getMethod("getCurrentActionContextStateName").invoke(zombie)
                    + " targetHealth=" + health(body);
            }
            return "ZOMBIE_DIRECTED status=pursuing distance=" + targetDistance
                + " targetHealth=" + health(body);
        }

        // This is only an acquisition bridge for off-slot NPCs. It deliberately does not
        // touch already-targeted zombies; their current target and subsequent combat stay vanilla.
        stage = "unprotect-acquired-target";
        body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, false);
        stage = "enable-acquired-zombie";
        zombie.getClass().getMethod("setUseless", boolean.class).invoke(zombie, false);
        zombie.getClass().getMethod("setCanWalk", boolean.class).invoke(zombie, true);
        stage = "spot-acquired-target";
        zombie.getClass().getMethod("spotted", movingObjectClass, boolean.class)
            .invoke(zombie, body, true);
        stage = "set-acquired-target";
        zombie.getClass().getMethod("setTarget", movingObjectClass).invoke(zombie, body);
        stage = "refresh-acquired-target-vector";
        float targetDistance = refreshZombieTargetVector(zombie, body);
        if (targetDistance <= ATTACK_VISIBILITY_ENVELOPE) {
            stage = "supply-acquired-target-visibility";
            supplyOffSlotAttackVisibility(zombie, body);
        }
        stage = "path-acquired-target";
        zombie.getClass().getMethod("pathToCharacter", gameCharacterClass).invoke(zombie, body);
        stage = "read-acquired-target";
        Object acquiredTarget = zombie.getClass().getMethod("getTarget").invoke(zombie);
        String status = acquiredTarget == body ? "acquired" : "rejected";
        stage = "read-acquired-target-health";
        return "ZOMBIE_DIRECTED status=" + status + " targetHealth=" + health(body);
        } catch (ReflectiveOperationException | RuntimeException exception) {
            throw new IllegalStateException("direct-zombie stage=" + stage, exception);
        }
    }

    static String zombieAttackDiagnostics(Object zombie, Object body)
        throws ReflectiveOperationException {
        Object target = zombie.getClass().getMethod("getTarget").invoke(zombie);
        int targetIndex = ((Number) body.getClass().getMethod("getIndex").invoke(body))
            .intValue();
        Object zombieSquare = zombie.getClass().getMethod("getCurrentSquare").invoke(zombie);
        boolean targetVisibilityBit = zombieSquare != null && (Boolean) zombieSquare.getClass()
            .getMethod("isCouldSee", int.class)
            .invoke(zombieSquare, targetIndex);
        float dx = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue()
            - ((Number) zombie.getClass().getMethod("getX").invoke(zombie)).floatValue();
        float dy = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue()
            - ((Number) zombie.getClass().getMethod("getY").invoke(zombie)).floatValue();
        float distance = (float) Math.sqrt(dx * dx + dy * dy);
        return "ZOMBIE_ATTACK_DIAGNOSTICS"
            + " targetMatches=" + (target == body)
            + " distance=" + distance
            + " targetSeenTime="
            + zombie.getClass().getMethod("getTargetSeenTime").invoke(zombie)
            + " shouldAttack=" + vanillaShouldAttack(zombie)
            + " engineTargetVisible="
            + zombie.getClass().getMethod("isTargetVisible").invoke(zombie)
            + " targetIndex=" + targetIndex
            + " targetVisibilityBit=" + targetVisibilityBit
            + " bCanSeeTarget="
            + zombie.getClass().getMethod("getVariableBoolean", String.class)
                .invoke(zombie, "bCanSeeTarget")
            + " bAttack="
            + zombie.getClass().getMethod("getVariableBoolean", String.class)
                .invoke(zombie, "bAttack")
            + " attackDidDamage="
            + zombie.getClass().getMethod("getVariableBoolean", String.class)
                .invoke(zombie, "AttackDidDamage")
            + " biteDone="
            + zombie.getClass().getMethod("getVariableBoolean", String.class)
                .invoke(zombie, "ZombieBiteDone")
            + " outcome=" + zombie.getClass().getMethod("getAttackOutcome").invoke(zombie)
            + " state=" + zombie.getClass().getMethod("getCurrentStateName").invoke(zombie)
            + " action="
            + zombie.getClass().getMethod("getCurrentActionContextStateName").invoke(zombie)
            + " targetAction="
            + body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
            + " targetAttackType="
            + body.getClass().getMethod("getVariableString", String.class)
                .invoke(body, "AttackType")
            + " targetHitReaction="
            + body.getClass().getMethod("getHitReaction").invoke(body)
            + " targetAttacking="
            + body.getClass().getMethod("isAttacking").invoke(body)
            + " targetAttackAnimation="
            + body.getClass().getMethod("isPerformingAttackAnimation").invoke(body)
            + " targetAimFloor="
            + body.getClass().getMethod("isAimAtFloor").invoke(body)
            + " attackedByMatches="
            + (body.getClass().getMethod("getAttackedBy").invoke(body) == zombie)
            + " targetHealth=" + health(body)
            + " injuredParts=" + injuredParts(body)
            + " bleedingParts=" + bleedingParts(body);
    }

    private static void supplyOffSlotAttackVisibility(Object zombie, Object body)
        throws ReflectiveOperationException {
        // IsoZombie.isTargetVisible() reads IsoGridSquare.isCouldSee(target.getIndex()).
        // A Knox shell deliberately uses an off-slot index and does not run updateLOS,
        // otherwise it corrupts the real player's visibility and cursor channels. Keep
        // only the close-range attack variables alive while the perception bridge owns
        // this exact target. The normal getShouldAttack() and collision line checks still
        // reject walls, floors, vehicles, protected targets, and invalid height.
        int playerIndex = ((Number) body.getClass().getMethod("getIndex").invoke(body))
            .intValue();
        Class<?> isoPlayerClass = Class.forName(
            "zombie.characters.IsoPlayer",
            false,
            body.getClass().getClassLoader()
        );
        Object players = isoPlayerClass.getField("players").get(null);
        if (playerIndex <= 0
            || playerIndex >= Array.getLength(players)
            || Array.get(players, playerIndex) != null) {
            throw new IllegalStateException(
                "Knox NPC visibility index is no longer unowned: " + playerIndex
            );
        }

        // IsoZombie.isTargetVisible() asks its current square whether the target's
        // player index could see it. The shell cannot run IsoPlayer.updateLOS()
        // because that also controls rendering, camera-adjacent state, music and
        // local-player alpha. Reserve only the unused index's could-see bit on the
        // zombie's current and immediately adjacent squares. The one-tile cushion
        // keeps the bit stable while a close zombie finishes a movement step.
        Object currentSquare = zombie.getClass().getMethod("getCurrentSquare").invoke(zombie);
        if (currentSquare != null) {
            int squareX = ((Number) currentSquare.getClass().getMethod("getX")
                .invoke(currentSquare)).intValue();
            int squareY = ((Number) currentSquare.getClass().getMethod("getY")
                .invoke(currentSquare)).intValue();
            int squareZ = ((Number) currentSquare.getClass().getMethod("getZ")
                .invoke(currentSquare)).intValue();
            Object cell = zombie.getClass().getMethod("getCell").invoke(zombie);
            Method getGridSquare = cell.getClass().getMethod(
                "getGridSquare",
                int.class,
                int.class,
                int.class
            );
            for (int offsetX = -1; offsetX <= 1; offsetX++) {
                for (int offsetY = -1; offsetY <= 1; offsetY++) {
                    Object square = getGridSquare.invoke(
                        cell,
                        squareX + offsetX,
                        squareY + offsetY,
                        squareZ
                    );
                    if (square != null) {
                        square.getClass().getMethod("setCouldSee", int.class, boolean.class)
                            .invoke(square, playerIndex, true);
                    }
                }
            }
        }

        Field canSeeTarget = findField(zombie.getClass(), "canSeeTarget");
        if (!canSeeTarget.canAccess(zombie)) {
            canSeeTarget.setAccessible(true);
        }
        canSeeTarget.setBoolean(zombie, true);
        float targetSeenTime = ((Number) zombie.getClass()
            .getMethod("getTargetSeenTime").invoke(zombie)).floatValue();
        if (targetSeenTime < MINIMUM_ATTACK_SEEN_TIME) {
            zombie.getClass().getMethod("setTargetSeenTime", float.class)
                .invoke(zombie, MINIMUM_ATTACK_SEEN_TIME);
        }
    }

    private static Field findField(Class<?> type, String name) throws NoSuchFieldException {
        Class<?> current = type;
        while (current != null) {
            try {
                return current.getDeclaredField(name);
            } catch (NoSuchFieldException ignored) {
                current = current.getSuperclass();
            }
        }
        throw new NoSuchFieldException(type.getName() + "." + name);
    }

    private static boolean vanillaShouldAttack(Object zombie)
        throws ReflectiveOperationException {
        Method method = zombie.getClass().getDeclaredMethod("getShouldAttack");
        if (!method.canAccess(zombie)) {
            method.setAccessible(true);
        }
        return (Boolean) method.invoke(zombie);
    }

    private static boolean canEnterAttackFrom(String action) {
        if (action == null) {
            return false;
        }
        String normalized = action.toLowerCase(java.util.Locale.ROOT);
        return "idle".equals(normalized)
            || "lunge".equals(normalized)
            || "walktoward".equals(normalized)
            || "pathfind".equals(normalized)
            || "turnalerted".equals(normalized);
    }

    private static float refreshZombieTargetVector(Object zombie, Object body)
        throws ReflectiveOperationException {
        float zombieX = ((Number) zombie.getClass().getMethod("getX").invoke(zombie)).floatValue();
        float zombieY = ((Number) zombie.getClass().getMethod("getY").invoke(zombie)).floatValue();
        float bodyX = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
        float bodyY = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();

        // Vanilla's attack eligibility reads this live vector, while pathing also uses
        // lastTargetSeen*. Off-slot NPCs do not run local-player LOS updates, so mirror
        // only those perception values rather than forcing AttackState ourselves.
        Object vector = zombie.getClass().getField("vectorToTarget").get(zombie);
        vector.getClass().getField("x").setFloat(vector, bodyX - zombieX);
        vector.getClass().getField("y").setFloat(vector, bodyY - zombieY);
        zombie.getClass().getField("lastTargetSeenX").setInt(zombie, (int) Math.floor(bodyX));
        zombie.getClass().getField("lastTargetSeenY").setInt(zombie, (int) Math.floor(bodyY));
        float bodyZ = ((Number) body.getClass().getMethod("getZ").invoke(body)).floatValue();
        zombie.getClass().getField("lastTargetSeenZ").setInt(zombie, (int) Math.floor(bodyZ));
        float dx = bodyX - zombieX;
        float dy = bodyY - zombieY;
        return (float) Math.sqrt(dx * dx + dy * dy);
    }

    private static void clampZombieAttackVector(Object zombie, float maximumLength)
        throws ReflectiveOperationException {
        Object vector = zombie.getClass().getField("vectorToTarget").get(zombie);
        float x = vector.getClass().getField("x").getFloat(vector);
        float y = vector.getClass().getField("y").getFloat(vector);
        float length = (float) Math.sqrt(x * x + y * y);
        if (length <= maximumLength || length <= 0.001f) {
            return;
        }
        float scale = maximumLength / length;
        vector.getClass().getField("x").setFloat(vector, x * scale);
        vector.getClass().getField("y").setFloat(vector, y * scale);
    }
}
