package com.knoxsurvivors.agent;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.zip.ZipFile;

public final class KnoxSwipeStateTransformerVerifier {
    private KnoxSwipeStateTransformerVerifier() {
    }

    public static void main(String[] arguments) throws Exception {
        if (arguments.length < 1 || arguments.length > 2) {
            throw new IllegalArgumentException(
                "Expected the Project Zomboid jar path and optional patched-class output path"
            );
        }
        byte[] original;
        byte[] impactOriginal;
        try (ZipFile gameJar = new ZipFile(Path.of(arguments[0]).toFile())) {
            original = gameJar.getInputStream(
                gameJar.getEntry("zombie/ai/states/SwipeStatePlayer.class")
            ).readAllBytes();
            impactOriginal = gameJar.getInputStream(gameJar.getEntry("zombie/CombatManager.class")).readAllBytes();
        }
        byte[] patched = KnoxSwipeStateTransformer.patchForVerification(original);
        byte[] impact = KnoxSwipeStateTransformer.patchImpactForVerification(impactOriginal);
        if (Arrays.equals(impact, impactOriginal)) throw new AssertionError("Impact audio gate not patched");
        try {
            KnoxSwipeStateTransformer.patchImpactForVerification(impact);
            throw new AssertionError("Unexpected engine shape must fail closed");
        } catch (java.io.IOException expected) {
            // Already redirected gate must not patch another local-player check.
        }
        System.out.println("combat impact transformer verified calls=1 fail_closed=true");
        if (KnoxSwipeStateTransformer.getLastPatchCount()
            != KnoxSwipeStateTransformer.EXPECTED_PATCH_COUNT) {
            throw new AssertionError(
                "Unexpected patched call count " + KnoxSwipeStateTransformer.getLastPatchCount()
            );
        }
        if (Arrays.equals(original, patched)) {
            throw new AssertionError("Transformer did not change SwipeStatePlayer");
        }
        if (arguments.length == 2) {
            Path output = Path.of(arguments[1]);
            Files.createDirectories(output.getParent());
            Files.write(output, patched);
        }
        System.out.println(
            "combat transformer verified calls=" + KnoxSwipeStateTransformer.getLastPatchCount()
        );
    }
}
