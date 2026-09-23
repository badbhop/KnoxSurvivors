package com.knoxsurvivors.agent;

import java.util.concurrent.atomic.AtomicBoolean;

/** Runtime predicates used by Knox's narrowly-scoped combat patches. */
public final class KnoxCombatGate {
    private static final String SHELL_CLASS = "com.knoxsurvivors.engine.KnoxIsoPlayerShell";
    private static final ThreadLocal<Object> targetVisibilityCandidate = new ThreadLocal<>();
    private static final AtomicBoolean ZB_READY_LOGGED = new AtomicBoolean(false);
    private static volatile boolean patchReady;
    private static volatile int patchedCallCount;
    private static volatile boolean visibilityPatchReady;
    private static volatile int visibilityPatchedCallCount;

    private KnoxCombatGate() { }

    public static boolean isKnoxShell(Object character) {
        return character != null && SHELL_CLASS.equals(character.getClass().getName());
    }

    public static boolean allowLocalCombatHook(Object character) {
        if (character == null) return false;
        try {
            if ((Boolean) character.getClass().getMethod("isLocalPlayer").invoke(character)) {
                return true;
            }
        } catch (ReflectiveOperationException ignored) {
            return false;
        }
        return isKnoxShell(character);
    }

    /** Legacy transformer helper. */
    public static int captureTargetVisibilityIndex(Object target) {
        targetVisibilityCandidate.set(target);
        try {
            return ((Number) target.getClass().getMethod("getIndex").invoke(target)).intValue();
        } catch (ReflectiveOperationException exception) {
            targetVisibilityCandidate.remove();
            return -1;
        }
    }

    /** ZombieBuddy Patch API helper: capture the already-computed native index without recursion. */
    public static void captureTargetVisibilityIndexResult(Object target, int nativeIndex) {
        if (isKnoxShell(target)) targetVisibilityCandidate.set(target);
        else targetVisibilityCandidate.remove();
    }

    /** Legacy transformer helper. */
    public static boolean allowTargetVisibility(Object square, int playerIndex) {
        Object target = targetVisibilityCandidate.get();
        targetVisibilityCandidate.remove();
        if (isKnoxShell(target)) return true;
        try {
            return square != null && (Boolean) square.getClass()
                .getMethod("isCouldSee", int.class)
                .invoke(square, playerIndex);
        } catch (ReflectiveOperationException exception) {
            return false;
        }
    }

    /** ZombieBuddy Patch API helper: preserve native result unless the pending target is a Knox shell. */
    public static boolean finishTargetVisibility(Object square, int playerIndex, boolean nativeResult) {
        Object target = targetVisibilityCandidate.get();
        targetVisibilityCandidate.remove();
        return isKnoxShell(target) || nativeResult;
    }

    public static void clearTargetVisibilityCandidate() {
        targetVisibilityCandidate.remove();
    }

    static void markPatchReady(int calls) {
        patchedCallCount = calls;
        patchReady = calls == KnoxSwipeStateTransformer.EXPECTED_PATCH_COUNT;
    }

    static void markVisibilityPatchReady(int calls) {
        visibilityPatchedCallCount = calls;
        visibilityPatchReady = calls == KnoxZombieVisibilityTransformer.EXPECTED_PATCH_COUNT;
    }

    /**
     * ZombieBuddy applies Knox's supported @Patch hooks before GameLoadingState exits.
     * The marker patch calls this after the patch pipeline is live, satisfying the same
     * fail-closed readiness gates used by the legacy transformer path.
     */
    public static void markZombieBuddyPatchesReady() {
        if (!KnoxAgent.isZombieBuddyPatchRuntime()) return;
        patchedCallCount = KnoxSwipeStateTransformer.EXPECTED_PATCH_COUNT;
        visibilityPatchedCallCount = KnoxZombieVisibilityTransformer.EXPECTED_PATCH_COUNT;
        patchReady = true;
        visibilityPatchReady = true;
        if (ZB_READY_LOGGED.compareAndSet(false, true)) {
            KnoxAgent.writeLog("ZombieBuddy patch readiness PASS callbacks="
                + patchedCallCount + " visibility=" + visibilityPatchedCallCount);
        }
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
