package com.knoxsurvivors.agent;

/** Runtime predicate used only by the narrowly patched player melee callbacks. */
public final class KnoxCombatGate {
    private static final String SHELL_CLASS = "com.knoxsurvivors.engine.KnoxIsoPlayerShell";
    private static final ThreadLocal<Object> targetVisibilityCandidate = new ThreadLocal<>();
    private static volatile boolean patchReady;
    private static volatile int patchedCallCount;
    private static volatile boolean visibilityPatchReady;
    private static volatile int visibilityPatchedCallCount;

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

    /**
     * Captures the target immediately before Build 42's {@code IsoZombie.isTargetVisible()}
     * asks a grid square for that target's player-lighting slot. Knox shells intentionally do
     * not own a local-player lighting slot, so that vanilla query cannot represent them.
     */
    public static int captureTargetVisibilityIndex(Object target) {
        targetVisibilityCandidate.set(target);
        try {
            return ((Number) target.getClass().getMethod("getIndex").invoke(target)).intValue();
        } catch (ReflectiveOperationException exception) {
            targetVisibilityCandidate.remove();
            return -1;
        }
    }

    /**
     * Preserves normal square lighting for real players. A contained Knox shell is visible here
     * only after the regular Knox zombie-awareness controller has selected it as the zombie's
     * live target; native pathing, collision, attack state, hit rolls, and BodyDamage remain
     * untouched.
     */
    public static boolean allowTargetVisibility(Object square, int playerIndex) {
        Object target = targetVisibilityCandidate.get();
        targetVisibilityCandidate.remove();
        if (target != null && SHELL_CLASS.equals(target.getClass().getName())) {
            return true;
        }
        try {
            return square != null && (Boolean) square.getClass()
                .getMethod("isCouldSee", int.class)
                .invoke(square, playerIndex);
        } catch (ReflectiveOperationException exception) {
            return false;
        }
    }

    static void markPatchReady(int calls) {
        patchedCallCount = calls;
        patchReady = calls == KnoxSwipeStateTransformer.EXPECTED_PATCH_COUNT;
    }

    static void markVisibilityPatchReady(int calls) {
        visibilityPatchedCallCount = calls;
        visibilityPatchReady = calls == KnoxZombieVisibilityTransformer.EXPECTED_PATCH_COUNT;
    }

    public static boolean isPatchReady() {
        return patchReady;
    }

    public static int getPatchedCallCount() {
        return patchedCallCount;
    }

    public static boolean isVisibilityPatchReady() {
        return visibilityPatchReady;
    }

    public static int getVisibilityPatchedCallCount() {
        return visibilityPatchedCallCount;
    }
}
