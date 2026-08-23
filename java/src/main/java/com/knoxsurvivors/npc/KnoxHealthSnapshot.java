package com.knoxsurvivors.npc;

import java.nio.ByteBuffer;
import java.util.Base64;

/** Complete engine BodyDamage state retained independently of the temporary IsoPlayer body. */
final class KnoxHealthSnapshot {
    private static final int SCHEMA_VERSION = 1;
    private static final int HEALTH_BUFFER_BYTES = 256 * 1024;

    private final int worldVersion;
    private final float health;
    private final int injuredParts;
    private final int bleedingParts;
    private final String healthBytes;

    private KnoxHealthSnapshot(
        int worldVersion,
        float health,
        int injuredParts,
        int bleedingParts,
        String healthBytes
    ) {
        this.worldVersion = worldVersion;
        this.health = health;
        this.injuredParts = injuredParts;
        this.bleedingParts = bleedingParts;
        this.healthBytes = healthBytes;
    }

    static KnoxHealthSnapshot capture(Object body) throws ReflectiveOperationException {
        Object damage = body.getClass().getMethod("getBodyDamage").invoke(body);
        ByteBuffer buffer = ByteBuffer.allocate(HEALTH_BUFFER_BYTES);
        damage.getClass().getMethod("save", ByteBuffer.class).invoke(damage, buffer);
        byte[] bytes = new byte[buffer.position()];
        buffer.flip();
        buffer.get(bytes);
        return new KnoxHealthSnapshot(
            worldVersion(body),
            KnoxHealthController.health(body),
            KnoxHealthController.injuredParts(body),
            KnoxHealthController.bleedingParts(body),
            Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
        );
    }

    void restore(Object body) throws ReflectiveOperationException {
        Object damage = body.getClass().getMethod("getBodyDamage").invoke(body);
        ByteBuffer buffer = ByteBuffer.wrap(Base64.getUrlDecoder().decode(healthBytes));
        damage.getClass().getMethod("load", ByteBuffer.class, int.class)
            .invoke(damage, buffer, worldVersion);
        damage.getClass().getMethod("calculateOverallHealth").invoke(damage);
    }

    String encode() {
        return SCHEMA_VERSION
            + "|" + worldVersion
            + "|" + health
            + "|" + injuredParts
            + "|" + bleedingParts
            + "|" + healthBytes;
    }

    static KnoxHealthSnapshot decode(String encoded) {
        String[] fields = encoded.split("\\|", -1);
        if (fields.length != 6 || Integer.parseInt(fields[0]) != SCHEMA_VERSION) {
            throw new IllegalArgumentException("Unsupported health snapshot schema");
        }
        return new KnoxHealthSnapshot(
            Integer.parseInt(fields[1]),
            Float.parseFloat(fields[2]),
            Integer.parseInt(fields[3]),
            Integer.parseInt(fields[4]),
            fields[5]
        );
    }

    String summary() {
        return "health=" + health
            + " injuredParts=" + injuredParts
            + " bleedingParts=" + bleedingParts;
    }

    private static int worldVersion(Object body) throws ReflectiveOperationException {
        Class<?> isoWorld = Class.forName(
            "zombie.iso.IsoWorld",
            false,
            body.getClass().getClassLoader()
        );
        return isoWorld.getField("WorldVersion").getInt(null);
    }
}
