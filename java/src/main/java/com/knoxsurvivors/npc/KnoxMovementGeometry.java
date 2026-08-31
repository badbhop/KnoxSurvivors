package com.knoxsurvivors.npc;

/** Z-aware movement comparisons shared by runtime ownership and captured native routes. */
final class KnoxMovementGeometry {
    private KnoxMovementGeometry() {
    }

    static boolean arrived(
        float currentX,
        float currentY,
        int currentZ,
        float targetX,
        float targetY,
        int targetZ,
        float tolerance
    ) {
        return currentZ == targetZ
            && distance2d(currentX, currentY, targetX, targetY) <= tolerance;
    }

    static boolean nodeReached(
        float currentX,
        float currentY,
        int currentZ,
        float nodeX,
        float nodeY,
        float nodeZ,
        float tolerance
    ) {
        return currentZ == floorZ(nodeZ)
            && distance2d(currentX, currentY, nodeX, nodeY) <= tolerance;
    }

    static float routeDistance(
        float firstX,
        float firstY,
        float firstZ,
        float secondX,
        float secondY,
        float secondZ
    ) {
        float dx = firstX - secondX;
        float dy = firstY - secondY;
        float dz = firstZ - secondZ;
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    static int floorZ(float z) {
        return (int) Math.floor(z);
    }

    private static float distance2d(float firstX, float firstY, float secondX, float secondY) {
        float dx = firstX - secondX;
        float dy = firstY - secondY;
        return (float) Math.sqrt(dx * dx + dy * dy);
    }
}
