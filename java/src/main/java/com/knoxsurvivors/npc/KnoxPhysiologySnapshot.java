package com.knoxsurvivors.npc;

import java.nio.ByteBuffer;
import java.util.Base64;

/** Engine-owned hunger, thirst, fatigue, endurance, nutrition, and sleep state. */
final class KnoxPhysiologySnapshot {
    private static final int SCHEMA_VERSION = 1;
    private static final int BUFFER_BYTES = 64 * 1024;

    private final int worldVersion;
    private final String statsBytes;
    private final String nutritionBytes;
    private final float asleepTime;
    private final double hoursSurvived;
    private final boolean asleep;
    private final float hunger;
    private final float thirst;
    private final float fatigue;
    private final float endurance;

    private KnoxPhysiologySnapshot(
        int worldVersion,
        String statsBytes,
        String nutritionBytes,
        float asleepTime,
        double hoursSurvived,
        boolean asleep,
        float hunger,
        float thirst,
        float fatigue,
        float endurance
    ) {
        this.worldVersion = worldVersion;
        this.statsBytes = statsBytes;
        this.nutritionBytes = nutritionBytes;
        this.asleepTime = asleepTime;
        this.hoursSurvived = hoursSurvived;
        this.asleep = asleep;
        this.hunger = hunger;
        this.thirst = thirst;
        this.fatigue = fatigue;
        this.endurance = endurance;
    }

    static KnoxPhysiologySnapshot capture(Object body) throws ReflectiveOperationException {
        Object stats = body.getClass().getMethod("getStats").invoke(body);
        Object nutrition = body.getClass().getMethod("getNutrition").invoke(body);
        return new KnoxPhysiologySnapshot(
            worldVersion(body),
            save(stats),
            save(nutrition),
            ((Number) body.getClass().getMethod("getAsleepTime").invoke(body)).floatValue(),
            ((Number) body.getClass().getMethod("getHoursSurvived").invoke(body)).doubleValue(),
            (Boolean) body.getClass().getMethod("isAsleep").invoke(body),
            stat(stats, "HUNGER"),
            stat(stats, "THIRST"),
            stat(stats, "FATIGUE"),
            stat(stats, "ENDURANCE")
        );
    }

    void restore(Object body) throws ReflectiveOperationException {
        Object stats = body.getClass().getMethod("getStats").invoke(body);
        stats.getClass().getMethod("load", ByteBuffer.class, int.class)
            .invoke(stats, decodeBytes(statsBytes), worldVersion);
        Object nutrition = body.getClass().getMethod("getNutrition").invoke(body);
        nutrition.getClass().getMethod("load", ByteBuffer.class)
            .invoke(nutrition, decodeBytes(nutritionBytes));
        body.getClass().getMethod("setAsleepTime", float.class).invoke(body, asleepTime);
        body.getClass().getMethod("setHoursSurvived", double.class).invoke(body, hoursSurvived);
        body.getClass().getMethod("setAsleep", boolean.class).invoke(body, asleep);
    }

    String encode() {
        return SCHEMA_VERSION
            + "|" + worldVersion
            + "|" + statsBytes
            + "|" + nutritionBytes
            + "|" + asleepTime
            + "|" + hoursSurvived
            + "|" + asleep
            + "|" + hunger
            + "|" + thirst
            + "|" + fatigue
            + "|" + endurance;
    }

    static KnoxPhysiologySnapshot decode(String encoded) {
        String[] fields = encoded.split("\\|", -1);
        if (fields.length != 11 || Integer.parseInt(fields[0]) != SCHEMA_VERSION) {
            throw new IllegalArgumentException("Unsupported physiology snapshot schema");
        }
        return new KnoxPhysiologySnapshot(
            Integer.parseInt(fields[1]),
            fields[2],
            fields[3],
            Float.parseFloat(fields[4]),
            Double.parseDouble(fields[5]),
            Boolean.parseBoolean(fields[6]),
            Float.parseFloat(fields[7]),
            Float.parseFloat(fields[8]),
            Float.parseFloat(fields[9]),
            Float.parseFloat(fields[10])
        );
    }

    String summary() {
        return "hunger=" + hunger
            + " thirst=" + thirst
            + " fatigue=" + fatigue
            + " endurance=" + endurance
            + " asleep=" + asleep;
    }

    private static String save(Object state) throws ReflectiveOperationException {
        ByteBuffer buffer = ByteBuffer.allocate(BUFFER_BYTES);
        state.getClass().getMethod("save", ByteBuffer.class).invoke(state, buffer);
        byte[] bytes = new byte[buffer.position()];
        buffer.flip();
        buffer.get(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static ByteBuffer decodeBytes(String encoded) {
        return ByteBuffer.wrap(Base64.getUrlDecoder().decode(encoded));
    }

    private static float stat(Object stats, String name) throws ReflectiveOperationException {
        Class<?> statClass = Class.forName(
            "zombie.characters.CharacterStat",
            false,
            stats.getClass().getClassLoader()
        );
        Object key = statClass.getField(name).get(null);
        return ((Number) stats.getClass().getMethod("get", statClass).invoke(stats, key))
            .floatValue();
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
