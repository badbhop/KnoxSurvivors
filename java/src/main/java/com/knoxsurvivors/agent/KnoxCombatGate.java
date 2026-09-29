package com.knoxsurvivors.agent;

import java.util.concurrent.atomic.AtomicBoolean;

/** Runtime predicates used by Knox's narrowly-scoped combat patches. */
public final class KnoxCombatGate {
    private static final String SHELL_CLASS = "com.knoxsurvivors.engine.KnoxIsoPlayerShell";
    private static final ThreadLocal<Object> targetVisibilityCandidate = new ThreadLocal<>();
    private static final AtomicBoolean RUNTIME_READY_LOGGED = new AtomicBoolean(false);
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

    static void markRuntimeReadyIfPatched() {
        if (patchReady && visibilityPatchReady && RUNTIME_READY_LOGGED.compareAndSet(false, true))
            KnoxAgent.writeLog("KnoxBridge required combat patches ready callbacks="
                + patchedCallCount + " visibility=" + visibilityPatchedCallCount);
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
