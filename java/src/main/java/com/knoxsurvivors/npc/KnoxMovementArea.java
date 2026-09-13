package com.knoxsurvivors.npc;

import java.util.List;

/** Transient movement permission for one duty route, never a safehouse boundary. */
final class KnoxMovementArea {
    final int minX, minY, maxX, maxY, z;
    private boolean entered;
    private boolean rejected;

    KnoxMovementArea(int minX, int minY, int maxX, int maxY, int z) {
        this.minX = Math.min(minX, maxX);
        this.minY = Math.min(minY, maxY);
        this.maxX = Math.max(minX, maxX);
        this.maxY = Math.max(minY, maxY);
        this.z = z;
    }

    boolean contains(float x, float y, float floor) {
        return Float.isFinite(x) && Float.isFinite(y) && Float.isFinite(floor)
            && x >= minX && x < (double) maxX + 1
            && y >= minY && y < (double) maxY + 1 && Math.abs(floor - z) < 0.01f;
    }

    boolean sameBounds(KnoxMovementArea other) {
        return other != null && minX == other.minX && minY == other.minY
            && maxX == other.maxX && maxY == other.maxY && z == other.z;
    }

    boolean allowsPosition(float x, float y, float floor) {
        boolean inside = contains(x, y, floor);
        if (entered && !inside) return false;
        entered |= inside;
        return true;
    }

    boolean acceptRoute(float x, float y, float floor, List<float[]> nodes) {
        entered |= contains(x, y, floor);
        boolean reached = entered;
        for (float[] node : nodes) {
            if (node == null || node.length < 3 || !Float.isFinite(node[0])
                || !Float.isFinite(node[1]) || !Float.isFinite(node[2])) {
                rejected = true;
                return false;
            }
            boolean inside = contains(node[0], node[1], node[2]);
            if (reached && !inside) {
                rejected = true;
                return false;
            }
            reached |= inside;
        }
        rejected = !reached;
        return !rejected;
    }

    boolean isRejected() { return rejected; }
}
