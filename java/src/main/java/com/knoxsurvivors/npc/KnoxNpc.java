package com.knoxsurvivors.npc;

import java.util.ArrayList;
import java.util.List;

/** Knox-owned identity paired with a temporary Project Zomboid IsoPlayer body. */
public final class KnoxNpc {
    private final String id;
    private final Object body;
    private final int spawnX;
    private final int spawnY;
    private final int spawnZ;
    private final List<float[]> movementRoute = new ArrayList<>();
    private int movementRouteIndex;

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
    }

    void clearMovementRoute() {
        movementRoute.clear();
        movementRouteIndex = 0;
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
        }
    }

    String describeMovementRoute() {
        return movementRouteIndex + "/" + movementRoute.size();
    }

    public String describe() {
        return id + "@" + spawnX + "," + spawnY + "," + spawnZ;
    }
}
