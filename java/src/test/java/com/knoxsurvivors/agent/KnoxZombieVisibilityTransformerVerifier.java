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
        System.out.println(
            "zombie visibility transformer verified calls="
                + KnoxZombieVisibilityTransformer.getLastPatchCount()
        );
    }
}
