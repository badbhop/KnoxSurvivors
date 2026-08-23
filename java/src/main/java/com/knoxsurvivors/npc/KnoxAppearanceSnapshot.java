package com.knoxsurvivors.npc;

import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

/** Exact engine visual plus the stable player-style identity fields Knox owns. */
final class KnoxAppearanceSnapshot {
    private static final int SCHEMA_VERSION = 1;
    private static final int VISUAL_BUFFER_BYTES = 64 * 1024;

    private final boolean female;
    private final int worldVersion;
    private final String visualBytes;
    private final String forename;
    private final String surname;
    private final String voicePrefix;
    private final int voiceType;
    private final float voicePitch;

    private KnoxAppearanceSnapshot(
        boolean female,
        int worldVersion,
        String visualBytes,
        String forename,
        String surname,
        String voicePrefix,
        int voiceType,
        float voicePitch
    ) {
        this.female = female;
        this.worldVersion = worldVersion;
        this.visualBytes = visualBytes;
        this.forename = forename;
        this.surname = surname;
        this.voicePrefix = voicePrefix;
        this.voiceType = voiceType;
        this.voicePitch = voicePitch;
    }

    static KnoxAppearanceSnapshot capture(Object body) throws ReflectiveOperationException {
        Object descriptor = invoke(body, "getDescriptor");
        Object visual = invoke(body, "getHumanVisual");
        int worldVersion = worldVersion(body);
        return new KnoxAppearanceSnapshot(
            (Boolean) invoke(body, "isFemale"),
            worldVersion,
            saveVisual(visual),
            (String) invoke(descriptor, "getForename"),
            (String) invoke(descriptor, "getSurname"),
            (String) invoke(descriptor, "getVoicePrefix"),
            ((Number) invoke(descriptor, "getVoiceType")).intValue(),
            ((Number) invoke(descriptor, "getVoicePitch")).floatValue()
        );
    }

    void restore(Object body) throws ReflectiveOperationException {
        Object descriptor = invoke(body, "getDescriptor");
        body.getClass().getMethod("setFemale", boolean.class).invoke(body, female);
        descriptor.getClass().getMethod("setFemale", boolean.class).invoke(descriptor, female);
        descriptor.getClass().getMethod("setForename", String.class).invoke(descriptor, forename);
        descriptor.getClass().getMethod("setSurname", String.class).invoke(descriptor, surname);
        descriptor.getClass().getMethod("setVoicePrefix", String.class).invoke(descriptor, voicePrefix);
        descriptor.getClass().getMethod("setVoiceType", int.class).invoke(descriptor, voiceType);
        descriptor.getClass().getMethod("setVoicePitch", float.class).invoke(descriptor, voicePitch);

        Object bodyVisual = invoke(body, "getHumanVisual");
        loadVisual(bodyVisual, visualBytes, worldVersion);
        Object descriptorVisual = invoke(descriptor, "getHumanVisual");
        invokeCompatible(descriptorVisual, "copyFrom", bodyVisual);
        invoke(body, "resetModelNextFrame");
    }

    String encode() {
        return SCHEMA_VERSION
            + "|" + (female ? 1 : 0)
            + "|" + worldVersion
            + "|" + visualBytes
            + "|" + text(forename)
            + "|" + text(surname)
            + "|" + text(voicePrefix == null ? "" : voicePrefix)
            + "|" + voiceType
            + "|" + voicePitch;
    }

    static KnoxAppearanceSnapshot decode(String encoded) {
        String[] fields = encoded.split("\\|", -1);
        if (fields.length != 9 || Integer.parseInt(fields[0]) != SCHEMA_VERSION) {
            throw new IllegalArgumentException("Unsupported appearance snapshot schema");
        }
        return new KnoxAppearanceSnapshot(
            "1".equals(fields[1]),
            Integer.parseInt(fields[2]),
            fields[3],
            untext(fields[4]),
            untext(fields[5]),
            untext(fields[6]),
            Integer.parseInt(fields[7]),
            Float.parseFloat(fields[8])
        );
    }

    String summary() {
        return (female ? "female" : "male") + " name=" + forename + "_" + surname;
    }

    private static String saveVisual(Object visual) throws ReflectiveOperationException {
        ByteBuffer buffer = ByteBuffer.allocate(VISUAL_BUFFER_BYTES);
        visual.getClass().getMethod("save", ByteBuffer.class).invoke(visual, buffer);
        byte[] bytes = new byte[buffer.position()];
        buffer.flip();
        buffer.get(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static void loadVisual(Object visual, String encoded, int version)
        throws ReflectiveOperationException {
        ByteBuffer buffer = ByteBuffer.wrap(Base64.getUrlDecoder().decode(encoded));
        visual.getClass().getMethod("load", ByteBuffer.class, int.class)
            .invoke(visual, buffer, version);
    }

    private static int worldVersion(Object body) throws ReflectiveOperationException {
        Class<?> isoWorld = Class.forName(
            "zombie.iso.IsoWorld",
            false,
            body.getClass().getClassLoader()
        );
        return isoWorld.getField("WorldVersion").getInt(null);
    }

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getMethod(name).invoke(target);
    }

    private static Object invokeCompatible(Object target, String name, Object argument)
        throws ReflectiveOperationException {
        for (Method method : target.getClass().getMethods()) {
            if (method.getName().equals(name)
                && method.getParameterCount() == 1
                && method.getParameterTypes()[0].isInstance(argument)) {
                return method.invoke(target, argument);
            }
        }
        throw new NoSuchMethodException(target.getClass().getName() + "." + name);
    }

    private static String text(String value) {
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }

    private static String untext(String value) {
        return new String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8);
    }
}
