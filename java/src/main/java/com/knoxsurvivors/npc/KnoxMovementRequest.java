package com.knoxsurvivors.npc;

/** Single-owner metadata for one engine movement request. */
final class KnoxMovementRequest {
    enum Change {
        START,
        KEEP,
        REPLACE
    }

    private static final float SAME_TARGET_EPSILON = 0.01f;

    private boolean active;
    private float targetX;
    private float targetY;
    private int targetZ;
    private boolean exactAdjacentCrossing;

    Change classify(float x, float y, int z, boolean crossing) {
        if (!active) {
            return Change.START;
        }
        return sameTarget(x, y, z, crossing) ? Change.KEEP : Change.REPLACE;
    }

    void activate(float x, float y, int z, boolean crossing) {
        targetX = x;
        targetY = y;
        targetZ = z;
        exactAdjacentCrossing = crossing;
        active = true;
    }

    void release() {
        active = false;
        targetX = 0.0f;
        targetY = 0.0f;
        targetZ = 0;
        exactAdjacentCrossing = false;
    }

    boolean isActive() {
        return active;
    }

    float targetX() {
        return targetX;
    }

    float targetY() {
        return targetY;
    }

    int targetZ() {
        return targetZ;
    }

    private boolean sameTarget(float x, float y, int z, boolean crossing) {
        return Math.abs(targetX - x) <= SAME_TARGET_EPSILON
            && Math.abs(targetY - y) <= SAME_TARGET_EPSILON
            && targetZ == z
            && exactAdjacentCrossing == crossing;
    }
}
