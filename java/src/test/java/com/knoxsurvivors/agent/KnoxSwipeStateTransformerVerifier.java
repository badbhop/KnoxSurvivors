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
        byte[] human = KnoxSwipeStateTransformer.patchHumanForVerification(impact);
        if (Arrays.equals(human, impact)) throw new AssertionError("Human pair gates not patched");
        try {
            KnoxSwipeStateTransformer.patchHumanForVerification(human);
            throw new AssertionError("Human gate shape must fail closed");
        } catch (java.io.IOException expected) { }
        verifyPairs();
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

    private static void verifyPairs() {
        if (!KnoxHumanCombatGate.usesPair(true, false, false, true, true)
            || KnoxHumanCombatGate.usesPair(false, false, false, true, true)
            || KnoxHumanCombatGate.usesPair(true, true, false, true, true)
            || KnoxHumanCombatGate.usesPair(true, false, true, true, true)
            || KnoxHumanCombatGate.usesPair(true, false, false, false, true)
            || KnoxHumanCombatGate.usesPair(true, false, false, true, false))
            throw new AssertionError("Only a registered single-player human pair uses the adapter");
        if (!KnoxHumanCombatGate.canHit(false, false, false, true, true)
            || KnoxHumanCombatGate.canHit(true, false, false, true, true)
            || KnoxHumanCombatGate.canHit(false, true, false, true, true)
            || KnoxHumanCombatGate.canHit(false, false, true, true, true)
            || KnoxHumanCombatGate.canHit(false, false, false, false, true)
            || KnoxHumanCombatGate.canHit(false, false, false, true, false))
            throw new AssertionError("Godmode/dead/detached bodies cannot bypass native protection");
        KnoxHumanCombatGate.Pairs pairs = new KnoxHumanCombatGate.Pairs();
        Object owner = new Object(), npc = new Object(), target = new Object(), other = new Object();
        pairs.put(owner, npc, target, 0);
        if (!pairs.contains(npc, target, 1) || !pairs.contains(target, npc, 1)
            || pairs.contains(npc, other, 1)) throw new AssertionError("Exact pair/self-defense scope");
        pairs.put(owner, npc, other, 2);
        if (pairs.contains(npc, target, 3) || !pairs.contains(npc, other, 3))
            throw new AssertionError("Replacing target must revoke previous pair");
        pairs.remove(owner);
        if (pairs.contains(npc, other, 4)) throw new AssertionError("Reset must revoke pair");
        pairs.put(owner, npc, target, 5);
        if (pairs.contains(npc, target, 5 + KnoxHumanCombatGate.Pairs.TTL))
            throw new AssertionError("Orphaned lease must expire");
        pairs.put(owner, npc, npc, 6);
        if (pairs.contains(npc, npc, 7)) throw new AssertionError("Self hit cannot be authorized");
        System.out.println("human pair gates verified calls=3 scope=true replacement=true cleanup=true expiry=true");
    }
}
