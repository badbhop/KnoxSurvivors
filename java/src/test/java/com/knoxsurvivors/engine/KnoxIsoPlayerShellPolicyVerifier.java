package com.knoxsurvivors.engine;

/** Verifies ownership policy encoded into the generated IsoPlayer shell. */
public final class KnoxIsoPlayerShellPolicyVerifier {
    private KnoxIsoPlayerShellPolicyVerifier() {
    }

    public static void main(String[] args) {
        if (KnoxIsoPlayerShellDefinition.localPlayerOverrideValue()) {
            throw new IllegalStateException("Knox shell must not claim local-player ownership");
        }
        System.out.println("IsoPlayer shell ownership policy verified localPlayer=false");
    }
}
