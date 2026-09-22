package com.knoxsurvivors.npc;

import java.util.Locale;

/** Pure walk/run/sprint selection for an already-owned movement request. */
final class KnoxLocomotionPolicy {
    private static final float RUN_REMAINING_DISTANCE = 2.0f;
    // Formation slots sit only a few tiles behind a sprinting leader.  Requiring
    // an eight-tile gap made an explicit sprint request visibly lag behind.
    private static final float SPRINT_REMAINING_DISTANCE = 2.5f;

    static final class Decision {
        private final boolean running;
        private final boolean sprinting;

        private Decision(boolean running, boolean sprinting) {
            this.running = running;
            this.sprinting = sprinting;
        }

        boolean running() {
            return running;
        }

        boolean sprinting() {
            return sprinting;
        }
    }

    private KnoxLocomotionPolicy() {
    }

    static Decision decide(
        String pace,
        float remainingDistance,
        float endurance,
        float fatigue,
        float health,
        boolean nativeCanSprint
    ) {
        String requested = pace == null ? "normal" : pace.toLowerCase(Locale.ROOT);
        boolean catchUp = "catchup".equals(requested);
        boolean asksToRun = "run".equals(requested) || "sprint".equals(requested)
            || (catchUp && remainingDistance > 3.0f);
        boolean asksToSprint = "sprint".equals(requested)
            || (catchUp && remainingDistance > 10.0f);

        boolean canRun = endurance > 0.22f && fatigue < 0.88f && health > 15.0f;
        boolean canSprint = nativeCanSprint
            && endurance > 0.48f && fatigue < 0.72f && health > 25.0f;
        boolean sprinting = asksToSprint
            && remainingDistance > SPRINT_REMAINING_DISTANCE
            && canSprint;
        boolean running = asksToRun
            && remainingDistance > RUN_REMAINING_DISTANCE
            && canRun;
        return new Decision(running || sprinting, sprinting);
    }
}
