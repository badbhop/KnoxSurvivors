package com.knoxsurvivors.npc;

/**
 * Small per-runtime transaction marker for a native corpse handoff.
 *
 * <p>The {@code IsoDeadBody} constructor has an immediate world side effect.  If
 * detaching the contained NPC shell fails after that constructor succeeds, the next
 * lifecycle tick must retry cleanup only; constructing another corpse would duplicate
 * the survivor's inventory and body.</p>
 */
final class KnoxCorpseRetirement {
    private boolean corpseCreated;
    private boolean reanimationRequired;
    private boolean reanimationScheduled;

    boolean corpseCreated() {
        return corpseCreated;
    }

    boolean reanimationRequired() {
        return reanimationRequired;
    }

    boolean reanimationScheduled() {
        return reanimationScheduled;
    }

    void markCorpseCreated(boolean requiresReanimation) {
        corpseCreated = true;
        reanimationRequired = requiresReanimation;
    }

    void markReanimationScheduled() {
        if (!corpseCreated || !reanimationRequired) {
            throw new IllegalStateException("cannot schedule reanimation before an eligible corpse exists");
        }
        reanimationScheduled = true;
    }

    void reset() {
        corpseCreated = false;
        reanimationRequired = false;
        reanimationScheduled = false;
    }
}
