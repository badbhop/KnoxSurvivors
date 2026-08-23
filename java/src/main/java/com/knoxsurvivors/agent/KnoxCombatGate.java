package com.knoxsurvivors.agent;

/** Runtime predicate used only by the narrowly patched player melee callbacks. */
public final class KnoxCombatGate {
    private static final String SHELL_CLASS = "com.knoxsurvivors.engine.KnoxIsoPlayerShell";
    private static volatile boolean patchReady;
    private static volatile int patchedCallCount;

    private KnoxCombatGate() {
    }

    public static boolean allowLocalCombatHook(Object character) {
        if (character == null) {
            return false;
        }
        try {
            if ((Boolean) character.getClass().getMethod("isLocalPlayer").invoke(character)) {
                return true;
            }
        } catch (ReflectiveOperationException ignored) {
            return false;
        }
        return SHELL_CLASS.equals(character.getClass().getName());
    }

    static void markPatchReady(int calls) {
        patchedCallCount = calls;
        patchReady = calls == KnoxSwipeStateTransformer.EXPECTED_PATCH_COUNT;
    }

    public static boolean isPatchReady() {
        return patchReady;
    }

    public static int getPatchedCallCount() {
        return patchedCallCount;
    }
}
