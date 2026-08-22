package com.knoxsurvivors.npc;

/** Knox-owned identity paired with a temporary Project Zomboid IsoPlayer body. */
public final class KnoxNpc {
    private final String id;
    private final Object body;
    private final int spawnX;
    private final int spawnY;
    private final int spawnZ;

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

    public String describe() {
        return id + "@" + spawnX + "," + spawnY + "," + spawnZ;
    }
}
