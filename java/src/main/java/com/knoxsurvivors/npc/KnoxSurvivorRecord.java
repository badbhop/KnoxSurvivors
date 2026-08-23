package com.knoxsurvivors.npc;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

/** Versioned persistent identity and world state independent of an IsoPlayer body. */
final class KnoxSurvivorRecord {
    static final int SCHEMA_VERSION = 1;

    final String id;
    final int x;
    final int y;
    final int z;
    final KnoxInventorySnapshot inventory;

    KnoxSurvivorRecord(String id, int x, int y, int z, KnoxInventorySnapshot inventory) {
        this.id = id;
        this.x = x;
        this.y = y;
        this.z = z;
        this.inventory = inventory;
    }

    String encode() {
        return SCHEMA_VERSION
            + "|" + text(id)
            + "|" + x
            + "|" + y
            + "|" + z
            + "|" + text(inventory.encode());
    }

    static KnoxSurvivorRecord decode(String encoded) {
        String[] fields = encoded.split("\\|", -1);
        if (fields.length != 6 || Integer.parseInt(fields[0]) != SCHEMA_VERSION) {
            throw new IllegalArgumentException("Unsupported survivor record schema");
        }
        return new KnoxSurvivorRecord(
            untext(fields[1]),
            Integer.parseInt(fields[2]),
            Integer.parseInt(fields[3]),
            Integer.parseInt(fields[4]),
            KnoxInventorySnapshot.decode(untext(fields[5]))
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
