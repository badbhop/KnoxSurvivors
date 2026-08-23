package com.knoxsurvivors.agent;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.Set;

/**
 * Redirects three local-player checks inside melee animation callbacks to a predicate
 * that also recognizes the Knox shell. The callback bodies remain the game's own code.
 */
public final class KnoxSwipeStateTransformer implements ClassFileTransformer {
    static final int EXPECTED_PATCH_COUNT = 3;
    private static final String TARGET_CLASS = "zombie/ai/states/SwipeStatePlayer";
    private static final String ORIGINAL_OWNER = "zombie/characters/IsoPlayer";
    private static final String ORIGINAL_NAME = "isLocalPlayer";
    private static final String ORIGINAL_DESCRIPTOR =
        "(Lzombie/characters/IsoGameCharacter;)Z";
    private static final String HELPER_OWNER = "com/knoxsurvivors/agent/KnoxCombatGate";
    private static final String HELPER_NAME = "allowLocalCombatHook";
    private static final String HELPER_DESCRIPTOR = "(Ljava/lang/Object;)Z";
    private static final Set<String> PATCHED_METHODS = Set.of(
        "OnAnimEvent_AttackCollisionCheck",
        "OnAnimEvent_PlaySwingSound",
        "OnAnimEvent_PlaySwingSoundAlways"
    );

    private static volatile int lastPatchCount;

    @Override
    public byte[] transform(
        ClassLoader loader,
        String className,
        Class<?> classBeingRedefined,
        ProtectionDomain protectionDomain,
        byte[] classfileBuffer
    ) {
        if (!TARGET_CLASS.equals(className)) {
            return null;
        }
        try {
            PatchResult result = patch(classfileBuffer);
            lastPatchCount = result.count;
            KnoxCombatGate.markPatchReady(result.count);
            if (result.count != EXPECTED_PATCH_COUNT) {
                KnoxAgent.writeLog(
                    "ERROR combat callback patch expected="
                        + EXPECTED_PATCH_COUNT
                        + " actual="
                        + result.count
                );
                return null;
            }
            KnoxAgent.writeLog("combat callback patch PASS calls=" + result.count);
            return result.bytes;
        } catch (Throwable throwable) {
            KnoxCombatGate.markPatchReady(0);
            KnoxAgent.writeLog(
                "ERROR combat callback patch "
                    + throwable.getClass().getName()
                    + ": "
                    + throwable.getMessage()
            );
            return null;
        }
    }

    static int getLastPatchCount() {
        return lastPatchCount;
    }

    static byte[] patchForVerification(byte[] bytes) throws IOException {
        PatchResult result = patch(bytes);
        lastPatchCount = result.count;
        return result.bytes;
    }

    private static PatchResult patch(byte[] original) throws IOException {
        ConstantPool pool = ConstantPool.read(original);
        int originalMethodRef = pool.findMethodRef(
            ORIGINAL_OWNER,
            ORIGINAL_NAME,
            ORIGINAL_DESCRIPTOR
        );
        if (originalMethodRef < 0) {
            throw new IOException("IsoPlayer.isLocalPlayer combat gate was not found");
        }

        int helperMethodRef = pool.count + 5;
        ByteArrayOutputStream additions = new ByteArrayOutputStream();
        try (DataOutputStream output = new DataOutputStream(additions)) {
            int ownerUtf8 = pool.count;
            int ownerClass = pool.count + 1;
            int nameUtf8 = pool.count + 2;
            int descriptorUtf8 = pool.count + 3;
            int nameAndType = pool.count + 4;
            writeUtf8(output, HELPER_OWNER);
            output.writeByte(7);
            output.writeShort(ownerUtf8);
            writeUtf8(output, HELPER_NAME);
            writeUtf8(output, HELPER_DESCRIPTOR);
            output.writeByte(12);
            output.writeShort(nameUtf8);
            output.writeShort(descriptorUtf8);
            output.writeByte(10);
            output.writeShort(ownerClass);
            output.writeShort(nameAndType);
        }

        byte[] expanded = new byte[original.length + additions.size()];
        System.arraycopy(original, 0, expanded, 0, 8);
        writeU2(expanded, 8, pool.count + 6);
        System.arraycopy(original, 10, expanded, 10, pool.endOffset - 10);
        byte[] appended = additions.toByteArray();
        System.arraycopy(appended, 0, expanded, pool.endOffset, appended.length);
        System.arraycopy(
            original,
            pool.endOffset,
            expanded,
            pool.endOffset + appended.length,
            original.length - pool.endOffset
        );

        int count = patchMethodCode(
            expanded,
            pool,
            pool.endOffset + appended.length,
            originalMethodRef,
            helperMethodRef
        );
        return new PatchResult(expanded, count);
    }

    private static int patchMethodCode(
        byte[] bytes,
        ConstantPool pool,
        int classBodyOffset,
        int originalMethodRef,
        int helperMethodRef
    ) throws IOException {
        int cursor = classBodyOffset + 6;
        int interfaceCount = readU2(bytes, cursor);
        cursor += 2 + interfaceCount * 2;
        int fieldCount = readU2(bytes, cursor);
        cursor += 2;
        for (int index = 0; index < fieldCount; index++) {
            cursor = skipMember(bytes, cursor);
        }

        int methodCount = readU2(bytes, cursor);
        cursor += 2;
        int patched = 0;
        for (int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
            cursor += 2;
            int nameIndex = readU2(bytes, cursor);
            cursor += 2;
            cursor += 2;
            int attributeCount = readU2(bytes, cursor);
            cursor += 2;
            String methodName = pool.utf8(nameIndex);
            for (int attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
                int attributeNameIndex = readU2(bytes, cursor);
                long attributeLength = readU4(bytes, cursor + 2);
                int content = cursor + 6;
                if (PATCHED_METHODS.contains(methodName)
                    && "Code".equals(pool.utf8(attributeNameIndex))) {
                    int codeLength = (int) readU4(bytes, content + 4);
                    int codeStart = content + 8;
                    int codeEnd = codeStart + codeLength;
                    for (int offset = codeStart; offset + 2 < codeEnd; offset++) {
                        if ((bytes[offset] & 0xFF) == 0xB8
                            && readU2(bytes, offset + 1) == originalMethodRef) {
                            writeU2(bytes, offset + 1, helperMethodRef);
                            patched++;
                        }
                    }
                }
                cursor = content + Math.toIntExact(attributeLength);
            }
        }
        return patched;
    }

    private static int skipMember(byte[] bytes, int cursor) {
        cursor += 6;
        int attributeCount = readU2(bytes, cursor);
        cursor += 2;
        for (int index = 0; index < attributeCount; index++) {
            long length = readU4(bytes, cursor + 2);
            cursor += 6 + Math.toIntExact(length);
        }
        return cursor;
    }

    private static void writeUtf8(DataOutputStream output, String value) throws IOException {
        output.writeByte(1);
        output.writeUTF(value);
    }

    private static int readU2(byte[] bytes, int offset) {
        return ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);
    }

    private static long readU4(byte[] bytes, int offset) {
        return ((long) (bytes[offset] & 0xFF) << 24)
            | ((long) (bytes[offset + 1] & 0xFF) << 16)
            | ((long) (bytes[offset + 2] & 0xFF) << 8)
            | (bytes[offset + 3] & 0xFFL);
    }

    private static void writeU2(byte[] bytes, int offset, int value) {
        bytes[offset] = (byte) (value >>> 8);
        bytes[offset + 1] = (byte) value;
    }

    private record PatchResult(byte[] bytes, int count) {
    }

    private static final class ConstantPool {
        final int count;
        final int endOffset;
        final int[] tags;
        final int[] first;
        final int[] second;
        final String[] utf8;

        private ConstantPool(
            int count,
            int endOffset,
            int[] tags,
            int[] first,
            int[] second,
            String[] utf8
        ) {
            this.count = count;
            this.endOffset = endOffset;
            this.tags = tags;
            this.first = first;
            this.second = second;
            this.utf8 = utf8;
        }

        static ConstantPool read(byte[] bytes) throws IOException {
            if (readU4(bytes, 0) != 0xCAFEBABEL) {
                throw new IOException("Invalid class file magic");
            }
            int count = readU2(bytes, 8);
            int[] tags = new int[count];
            int[] first = new int[count];
            int[] second = new int[count];
            String[] utf8 = new String[count];
            int cursor = 10;
            for (int index = 1; index < count; index++) {
                int tag = bytes[cursor++] & 0xFF;
                tags[index] = tag;
                switch (tag) {
                    case 1 -> {
                        int length = readU2(bytes, cursor);
                        cursor += 2;
                        utf8[index] = new String(
                            bytes,
                            cursor,
                            length,
                            java.nio.charset.StandardCharsets.UTF_8
                        );
                        cursor += length;
                    }
                    case 3, 4 -> cursor += 4;
                    case 5, 6 -> {
                        cursor += 8;
                        index++;
                    }
                    case 7, 8, 16, 19, 20 -> {
                        first[index] = readU2(bytes, cursor);
                        cursor += 2;
                    }
                    case 9, 10, 11, 12, 17, 18 -> {
                        first[index] = readU2(bytes, cursor);
                        second[index] = readU2(bytes, cursor + 2);
                        cursor += 4;
                    }
                    case 15 -> cursor += 3;
                    default -> throw new IOException("Unsupported constant-pool tag " + tag);
                }
            }
            return new ConstantPool(count, cursor, tags, first, second, utf8);
        }

        String utf8(int index) {
            return index > 0 && index < utf8.length ? utf8[index] : null;
        }

        int findMethodRef(String owner, String name, String descriptor) {
            for (int index = 1; index < count; index++) {
                if (tags[index] != 10) {
                    continue;
                }
                int classIndex = first[index];
                int nameAndTypeIndex = second[index];
                if (tags[classIndex] == 7
                    && owner.equals(utf8(first[classIndex]))
                    && tags[nameAndTypeIndex] == 12
                    && name.equals(utf8(first[nameAndTypeIndex]))
                    && descriptor.equals(utf8(second[nameAndTypeIndex]))) {
                    return index;
                }
            }
            return -1;
        }
    }
}
