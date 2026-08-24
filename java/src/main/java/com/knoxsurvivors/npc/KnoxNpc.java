package com.knoxsurvivors.npc;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/** Knox-owned identity paired with a temporary Project Zomboid IsoPlayer body. */
public final class KnoxNpc {
    private final String id;
    private final Object body;
    private final int spawnX;
    private final int spawnY;
    private final int spawnZ;
    private final List<float[]> movementRoute = new ArrayList<>();
    private int movementRouteIndex;
    private String movementTraversalState = "NONE";
    private final Set<String> movementTraversalEvidence = new LinkedHashSet<>();
    private Object traversalInteractionTarget;
    private String traversalInteractionStage = "NONE";
    private boolean climbingAllowed = true;
    private boolean hasProtectedArea;
    private int protectedMinX;
    private int protectedMinY;
    private int protectedMaxX;
    private int protectedMaxY;

    KnoxNpc(String id, Object body, int spawnX, int spawnY, int spawnZ) {
        this.id = id;
        this.body = body;
        this.spawnX = spawnX;
        this.spawnY = spawnY;
        this.spawnZ = spawnZ;
    }

    public String getId() {
        return id;
    }

    Object getBody() {
        return body;
    }

    void setMovementRoute(List<float[]> nodes) {
        movementRoute.clear();
        movementRoute.addAll(nodes);
        movementRouteIndex = 0;
        movementTraversalState = "ROUTE_READY";
        movementTraversalEvidence.clear();
        clearTraversalInteraction();
    }

    void clearMovementRoute() {
        movementRoute.clear();
        movementRouteIndex = 0;
        movementTraversalState = "NONE";
        movementTraversalEvidence.clear();
        clearTraversalInteraction();
    }

    boolean hasMovementRoute() {
        return movementRouteIndex < movementRoute.size();
    }

    float[] currentMovementNode() {
        return hasMovementRoute() ? movementRoute.get(movementRouteIndex) : null;
    }

    void advanceMovementRoute() {
        if (hasMovementRoute()) {
            movementRouteIndex++;
            clearTraversalInteraction();
        }
    }

    void useTraversalInteractionTarget(Object target) {
        if (traversalInteractionTarget != target) {
            traversalInteractionTarget = target;
            traversalInteractionStage = "NONE";
        }
    }

    Object getTraversalInteractionTarget() {
        return traversalInteractionTarget;
    }

    boolean isClimbingAllowed() {
        return climbingAllowed;
    }

    void setClimbingAllowed(boolean allowed) {
        climbingAllowed = allowed;
    }

    void setProtectedArea(int minX, int minY, int maxX, int maxY) {
        protectedMinX = Math.min(minX, maxX);
        protectedMinY = Math.min(minY, maxY);
        protectedMaxX = Math.max(minX, maxX);
        protectedMaxY = Math.max(minY, maxY);
        hasProtectedArea = true;
    }

    void clearProtectedArea() {
        hasProtectedArea = false;
    }

    boolean isProtectedStructureEdge(int currentX, int currentY, int nextX, int nextY) {
        if (!hasProtectedArea) {
            return false;
        }
        return insideProtectedArea(currentX, currentY) || insideProtectedArea(nextX, nextY);
    }

    private boolean insideProtectedArea(int x, int y) {
        return x >= protectedMinX && x <= protectedMaxX
            && y >= protectedMinY && y <= protectedMaxY;
    }

    String getTraversalInteractionStage() {
        return traversalInteractionStage;
    }

    void setTraversalInteractionStage(String stage) {
        traversalInteractionStage = stage;
    }

    private void clearTraversalInteraction() {
        traversalInteractionTarget = null;
        traversalInteractionStage = "NONE";
    }

    void setMovementTraversalState(String state) {
        movementTraversalState = state;
        if (!"CLEAR".equals(state) && !"ROUTE_READY".equals(state)) {
            movementTraversalEvidence.add(state);
        }
    }

    boolean hasMovementTraversalEvidence(String state) {
        return movementTraversalEvidence.contains(state);
    }

    String describeMovementRoute() {
        float[] node = currentMovementNode();
        String next = node == null ? "none" : node[0] + "," + node[1] + "," + node[2];
        return movementRouteIndex
            + "/"
            + movementRoute.size()
            + " next="
            + next
            + " traversal="
            + movementTraversalState
            + " evidence="
            + movementTraversalEvidence;
    }

    public String describe() {
        return id + "@" + spawnX + "," + spawnY + "," + spawnZ;
    }
}
