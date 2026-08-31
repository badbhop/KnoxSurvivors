package com.knoxsurvivors.npc;

/** Focused verifier for the contained corpse-to-native-reanimation handoff. */
public final class KnoxNpcRegistryVerifier {
    private KnoxNpcRegistryVerifier() {
    }

    public static void main(String[] arguments) throws Exception {
        FakeBody turns = new FakeBody(true);
        FakeCorpse scheduled = new FakeCorpse();
        if (!KnoxNpcRegistry.scheduleNativeReanimation(turns, scheduled)) {
            throw new IllegalStateException("turning survivor was not scheduled");
        }
        if (scheduled.reanimateLaterCalls != 1) {
            throw new IllegalStateException("native corpse schedule was not called exactly once");
        }

        FakeBody staysDead = new FakeBody(false);
        FakeCorpse ordinary = new FakeCorpse();
        if (KnoxNpcRegistry.scheduleNativeReanimation(staysDead, ordinary)) {
            throw new IllegalStateException("non-turning survivor was scheduled");
        }
        if (ordinary.reanimateLaterCalls != 0) {
            throw new IllegalStateException("ordinary corpse was incorrectly scheduled");
        }

        KnoxCorpseRetirement handoff = new KnoxCorpseRetirement();
        handoff.markCorpseCreated(true);
        handoff.markReanimationScheduled();
        if (!handoff.corpseCreated() || !handoff.reanimationRequired()
            || !handoff.reanimationScheduled()) {
            throw new IllegalStateException("corpse handoff state was not retained for cleanup retry");
        }
        handoff.reset();
        if (handoff.corpseCreated() || handoff.reanimationRequired()
            || handoff.reanimationScheduled()) {
            throw new IllegalStateException("corpse handoff state leaked after teardown");
        }
        System.out.println(
            "corpse lifecycle verified native-predicate=true native-schedule=true cleanup-retry=true"
        );
    }

    public static final class FakeBody {
        private final boolean shouldTurn;

        public FakeBody(boolean shouldTurn) {
            this.shouldTurn = shouldTurn;
        }

        public boolean shouldBecomeZombieAfterDeath() {
            return shouldTurn;
        }
    }

    public static final class FakeCorpse {
        private int reanimateLaterCalls;

        public void reanimateLater() {
            reanimateLaterCalls++;
        }
    }
}
