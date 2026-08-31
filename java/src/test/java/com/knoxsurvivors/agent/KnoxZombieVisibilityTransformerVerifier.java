package com.knoxsurvivors.agent;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.zip.ZipFile;

/** Verifies the exact Build 42.20.3 target-visibility adapter before staging the agent. */
public final class KnoxZombieVisibilityTransformerVerifier {
    private KnoxZombieVisibilityTransformerVerifier() {
    }

    public static void main(String[] arguments) throws Exception {
        if (arguments.length != 1) {
            throw new IllegalArgumentException("Expected the Project Zomboid jar path");
        }
        byte[] original;
        try (ZipFile gameJar = new ZipFile(Path.of(arguments[0]).toFile())) {
            original = gameJar.getInputStream(
                gameJar.getEntry("zombie/characters/IsoZombie.class")
            ).readAllBytes();
        }
        byte[] patched = KnoxZombieVisibilityTransformer.patchForVerification(original);
        if (KnoxZombieVisibilityTransformer.getLastPatchCount()
            != KnoxZombieVisibilityTransformer.EXPECTED_PATCH_COUNT) {
            throw new AssertionError(
                "Unexpected patched call count " + KnoxZombieVisibilityTransformer.getLastPatchCount()
            );
        }
        if (Arrays.equals(original, patched)) {
            throw new AssertionError("Transformer did not change IsoZombie");
        }
        KnoxCombatGate.markVisibilityPatchReady(
            KnoxZombieVisibilityTransformer.getLastPatchCount()
        );
        if (!KnoxCombatGate.isVisibilityPatchReady()) {
            throw new AssertionError("Visibility patch readiness was not established");
        }
        FakeTarget ordinaryTarget = new FakeTarget(2);
        KnoxCombatGate.captureTargetVisibilityIndex(ordinaryTarget);
        if (KnoxCombatGate.allowTargetVisibility(new FakeSquare(false), 2)) {
            throw new AssertionError("Ordinary target bypassed square visibility");
        }
        KnoxCombatGate.captureTargetVisibilityIndex(ordinaryTarget);
        if (!KnoxCombatGate.allowTargetVisibility(new FakeSquare(true), 2)) {
            throw new AssertionError("Ordinary target lost square visibility");
        }
        System.out.println(
            "zombie visibility transformer verified calls="
                + KnoxZombieVisibilityTransformer.getLastPatchCount()
        );
    }

    public static final class FakeTarget {
        private final int index;

        FakeTarget(int index) {
            this.index = index;
        }

        public int getIndex() {
            return index;
        }
    }

    public static final class FakeSquare {
        private final boolean visible;

        FakeSquare(boolean visible) {
            this.visible = visible;
        }

        public boolean isCouldSee(int index) {
            return visible;
        }
    }
}
