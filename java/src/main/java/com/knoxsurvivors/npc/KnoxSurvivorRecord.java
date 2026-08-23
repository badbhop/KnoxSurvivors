package com.knoxsurvivors.npc;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

/** Versioned persistent identity and world state independent of an IsoPlayer body. */
final class KnoxSurvivorRecord {
    static final int SCHEMA_VERSION = 4;

    final String id;
    final int x;
    final int y;
    final int z;
    final float positionX;
    final float positionY;
    final KnoxAppearanceSnapshot appearance;
    final KnoxInventorySnapshot inventory;
    final KnoxHealthSnapshot health;

    KnoxSurvivorRecord(
        String id,
        int x,
        int y,
        int z,
        float positionX,
        float positionY,
        KnoxAppearanceSnapshot appearance,
        KnoxInventorySnapshot inventory,
        KnoxHealthSnapshot health
    ) {
        this.id = id;
        this.x = x;
        this.y = y;
        this.z = z;
        this.positionX = positionX;
        this.positionY = positionY;
        this.appearance = appearance;
        this.inventory = inventory;
        this.health = health;
    }

    String encode() {
        return SCHEMA_VERSION
            + "|" + text(id)
            + "|" + x
            + "|" + y
            + "|" + z
            + "|" + positionX
            + "|" + positionY
            + "|" + text(appearance.encode())
            + "|" + text(inventory.encode())
            + "|" + text(health.encode());
    }

    static KnoxSurvivorRecord decode(String encoded) {
        String[] fields = encoded.split("\\|", -1);
        int version = Integer.parseInt(fields[0]);
        if (version == 2 && fields.length == 7) {
            int x = Integer.parseInt(fields[2]);
            int y = Integer.parseInt(fields[3]);
            return new KnoxSurvivorRecord(
                untext(fields[1]),
                x,
                y,
                Integer.parseInt(fields[4]),
                x + 0.5f,
                y + 0.5f,
                KnoxAppearanceSnapshot.decode(untext(fields[5])),
                KnoxInventorySnapshot.decode(untext(fields[6])),
                null
            );
        }
        if (version == 3 && fields.length == 9) {
            return new KnoxSurvivorRecord(
                untext(fields[1]),
                Integer.parseInt(fields[2]),
                Integer.parseInt(fields[3]),
                Integer.parseInt(fields[4]),
                Float.parseFloat(fields[5]),
                Float.parseFloat(fields[6]),
                KnoxAppearanceSnapshot.decode(untext(fields[7])),
                KnoxInventorySnapshot.decode(untext(fields[8])),
                null
            );
        }
        if (version != SCHEMA_VERSION || fields.length != 10) {
            throw new IllegalArgumentException("Unsupported survivor record schema");
        }
        return new KnoxSurvivorRecord(
            untext(fields[1]),
            Integer.parseInt(fields[2]),
            Integer.parseInt(fields[3]),
            Integer.parseInt(fields[4]),
            Float.parseFloat(fields[5]),
            Float.parseFloat(fields[6]),
            KnoxAppearanceSnapshot.decode(untext(fields[7])),
            KnoxInventorySnapshot.decode(untext(fields[8])),
            KnoxHealthSnapshot.decode(untext(fields[9]))
        );
    }

    private static String text(String value) {
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }

    private static String untext(String value) {
        return new String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8);
    }
}
