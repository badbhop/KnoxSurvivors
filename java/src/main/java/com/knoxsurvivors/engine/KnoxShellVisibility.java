package com.knoxsurvivors.engine;

import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

/**
 * Maps a contained NPC shell onto the real local player's fog-of-war channel.
 *
 * <p>The shell intentionally cannot run {@code IsoPlayer.updateLOS()}: that
 * method owns a player render slot and would corrupt the real player's view.
 * Rendering therefore asks the already-updated local player channel whether
 * the shell's current square is visible. This is deliberately separate from
 * the zombie perception bridge; a zombie may know about a survivor without
 * granting the player vision through a wall. Party membership is retained as
 * gameplay state, but never overrides line of sight: companions must not
 * shine through walls or disappear abruptly when the camera turns.</p>
 */
public final class KnoxShellVisibility {
    private static final int VIEWER_SLOTS = 4;
    private static final float FADE_PER_SECOND = 5.0F;
    private static final Map<Object, FadeState> fadeStates = Collections.synchronizedMap(
        new WeakHashMap<>()
    );
    private static final Set<Object> partyVisible = Collections.newSetFromMap(
        Collections.synchronizedMap(new WeakHashMap<>())
    );

    private KnoxShellVisibility() {
    }

    public static void setPartyVisible(Object shell, boolean visible) {
        if (shell == null) {
            return;
        }
        if (visible) {
            partyVisible.add(shell);
        } else {
            partyVisible.remove(shell);
        }
    }

    public static boolean isPartyVisible(Object shell) {
        return shell != null && partyVisible.contains(shell);
    }

    public static float getAlpha(Object shell) {
        return alpha(shell, 0);
    }

    public static float getAlpha(Object shell, int viewerIndex) {
        return alpha(shell, viewerIndex);
    }

    private static float alpha(Object shell, int viewerIndex) {
        int slot = Math.max(0, Math.min(VIEWER_SLOTS - 1, viewerIndex));
        // Companions are party members in the same way a split-screen player
        // is. Keep their shell renderable when they pass behind the camera or
        // a short occluding edge, otherwise turning around causes them to
        // disappear and reappear while their movement continues. This is a
        // render visibility choice only; it does not grant zombie awareness,
        // targeting, or wall traversal.
        boolean visible = isPartyVisible(shell) || isVisible(shell, viewerIndex);
        long now = System.nanoTime();
        synchronized (fadeStates) {
            FadeState state = fadeStates.computeIfAbsent(shell, ignored -> new FadeState(now));
            long previous = state.updatedAt[slot];
            state.updatedAt[slot] = now;
            float elapsed = Math.min(0.25F, Math.max(0.0F, (now - previous) / 1_000_000_000.0F));
            float target = visible ? 1.0F : 0.0F;
            float step = FADE_PER_SECOND * elapsed;
            if (state.alpha[slot] < target) {
                state.alpha[slot] = Math.min(target, state.alpha[slot] + step);
            } else if (state.alpha[slot] > target) {
                state.alpha[slot] = Math.max(target, state.alpha[slot] - step);
            }
            return state.alpha[slot];
        }
    }

    private static boolean isVisible(Object shell, int requestedViewerIndex) {
        try {
            Object square = shell.getClass().getMethod("getSquare").invoke(shell);
            if (square == null) {
                return false;
            }
            int viewerIndex = resolveLocalViewerIndex(requestedViewerIndex);
            // isCanSee is the real, current LOS result. isCouldSee includes explored
            // or potentially visible squares and would leak survivors through walls.
            return (Boolean) square.getClass().getMethod("isCanSee", int.class)
                .invoke(square, viewerIndex);
        } catch (ReflectiveOperationException exception) {
            // Never turn a temporary load-order issue into an invisible, stuck shell.
            return true;
        }
    }

    private static int resolveLocalViewerIndex(int requestedViewerIndex) {
        try {
            Class<?> isoPlayer = Class.forName("zombie.characters.IsoPlayer");
            Object players = isoPlayer.getField("players").get(null);
            Method isLocalPlayer = isoPlayer.getMethod("isLocalPlayer");
            int count = Array.getLength(players);
            if (requestedViewerIndex >= 0 && requestedViewerIndex < count) {
                Object requested = Array.get(players, requestedViewerIndex);
                if (requested != null && (Boolean) isLocalPlayer.invoke(requested)) {
                    return requestedViewerIndex;
                }
            }
            for (int index = 0; index < count; index++) {
                Object player = Array.get(players, index);
                if (player != null && (Boolean) isLocalPlayer.invoke(player)) {
                    return index;
                }
            }
        } catch (ReflectiveOperationException ignored) {
            // See the initialization note below.
        }
        // During early load the actual player slot may not be populated yet.
        // Keep the shell visible until the first normal LOS update rather than
        // making it permanently disappear because of initialization order.
        return 0;
    }

    private static final class FadeState {
        private final float[] alpha = new float[VIEWER_SLOTS];
        private final long[] updatedAt = new long[VIEWER_SLOTS];

        private FadeState(long now) {
            for (int index = 0; index < VIEWER_SLOTS; index++) {
                alpha[index] = 1.0F;
                updatedAt[index] = now;
            }
        }
    }
}
