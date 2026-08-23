package com.knoxsurvivors.npc;

import java.util.Collection;

/** Reads and prepares the engine-owned health state used by Knox survivor bodies. */
final class KnoxHealthController {
    private static final float FULL_PART_HEALTH = 99.999f;

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
        body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, false);
        zombie.getClass().getMethod("setUseless", boolean.class).invoke(zombie, false);
        zombie.getClass().getMethod("setCanWalk", boolean.class).invoke(zombie, true);
        zombie.getClass().getMethod("setTarget", movingObjectClass).invoke(zombie, body);
        zombie.getClass().getMethod("spotted", movingObjectClass, boolean.class)
            .invoke(zombie, body, true);
        zombie.getClass().getMethod("pathToCharacter", gameCharacterClass).invoke(zombie, body);
        return "ZOMBIE_DIRECTED targetHealth=" + health(body);
    }
}
