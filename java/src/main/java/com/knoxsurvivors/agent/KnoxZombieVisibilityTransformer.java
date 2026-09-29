package com.knoxsurvivors.agent;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;

/**
 * Adapts the one local-player-lighting lookup in {@code IsoZombie.isTargetVisible()} for the
 * contained Knox IsoPlayer shell. It does not alter target selection, pathing, attack states,
 * collision, animation callbacks, or damage.
 */
public final class KnoxZombieVisibilityTransformer implements ClassFileTransformer {
    static final int EXPECTED_PATCH_COUNT = 2;
    private static final String TARGET_CLASS = "zombie/characters/IsoZombie";
    private static final String TARGET_METHOD = "isTargetVisible";
    private static final String INDEX_OWNER = "zombie/characters/IsoPlayer";
    private static final String INDEX_NAME = "getIndex";
    private static final String INDEX_DESCRIPTOR = "()I";
    private static final String SQUARE_OWNER = "zombie/iso/IsoGridSquare";
    private static final String SQUARE_NAME = "isCouldSee";
    private static final String SQUARE_DESCRIPTOR = "(I)Z";
    private static final String HELPER_OWNER = "com/knoxsurvivors/agent/KnoxCombatGate";
    private static final String CAPTURE_NAME = "captureTargetVisibilityIndex";
    private static final String CAPTURE_DESCRIPTOR = "(Ljava/lang/Object;)I";
    private static final String VISIBILITY_NAME = "allowTargetVisibility";
    private static final String VISIBILITY_DESCRIPTOR = "(Ljava/lang/Object;I)Z";

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
            KnoxCombatGate.markVisibilityPatchReady(result.count);
            KnoxCombatGate.markRuntimeReadyIfPatched();
            if (result.count != EXPECTED_PATCH_COUNT) {
                KnoxAgent.writeLog(
                    "ERROR zombie visibility patch expected="
                        + EXPECTED_PATCH_COUNT
                        + " actual="
                        + result.count
                );
                return null;
            }
            KnoxAgent.writeLog("zombie visibility patch PASS calls=" + result.count);
            return result.bytes;
        } catch (Throwable throwable) {
            KnoxCombatGate.markVisibilityPatchReady(0);
            KnoxAgent.writeLog(
                "ERROR zombie visibility patch "
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
        int originalIndex = pool.findMethodRef(INDEX_OWNER, INDEX_NAME, INDEX_DESCRIPTOR);
        int originalVisibility = pool.findMethodRef(SQUARE_OWNER, SQUARE_NAME, SQUARE_DESCRIPTOR);
        if (originalIndex < 0 || originalVisibility < 0) {
            throw new IOException("IsoZombie target visibility gate was not found");
        }

        int captureRef = pool.count + 5;
        int visibilityRef = pool.count + 11;
        ByteArrayOutputStream additions = new ByteArrayOutputStream();
        try (DataOutputStream output = new DataOutputStream(additions)) {
            writeMethodRef(
                output,
                pool.count,
                HELPER_OWNER,
                CAPTURE_NAME,
                CAPTURE_DESCRIPTOR
            );
            writeMethodRef(
                output,
                pool.count + 6,
                HELPER_OWNER,
                VISIBILITY_NAME,
                VISIBILITY_DESCRIPTOR
            );
        }
        byte[] expanded = expandConstantPool(original, pool, additions.toByteArray(), 12);
        int count = patchMethodCode(
            expanded,
            pool,
            pool.endOffset + additions.size(),
            originalIndex,
            captureRef,
            originalVisibility,
            visibilityRef
        );
        return new PatchResult(expanded, count);
    }

    private static void writeMethodRef(
        DataOutputStream output,
        int firstEntry,
        String owner,
        String name,
        String descriptor
    ) throws IOException {
        int ownerUtf8 = firstEntry;
        int ownerClass = firstEntry + 1;
        int nameUtf8 = firstEntry + 2;
        int descriptorUtf8 = firstEntry + 3;
        int nameAndType = firstEntry + 4;
        writeUtf8(output, owner);
        output.writeByte(7);
        output.writeShort(ownerUtf8);
        writeUtf8(output, name);
        writeUtf8(output, descriptor);
        output.writeByte(12);
        output.writeShort(nameUtf8);
        output.writeShort(descriptorUtf8);
        output.writeByte(10);
        output.writeShort(ownerClass);
        output.writeShort(nameAndType);
    }

    private static byte[] expandConstantPool(
        byte[] original,
        ConstantPool pool,
        byte[] additions,
        int newEntries
    ) {
        byte[] expanded = new byte[original.length + additions.length];
        System.arraycopy(original, 0, expanded, 0, 8);
        writeU2(expanded, 8, pool.count + newEntries);
        System.arraycopy(original, 10, expanded, 10, pool.endOffset - 10);
        System.arraycopy(additions, 0, expanded, pool.endOffset, additions.length);
        System.arraycopy(
            original,
            pool.endOffset,
            expanded,
            pool.endOffset + additions.length,
            original.length - pool.endOffset
        );
        return expanded;
    }

    private static int patchMethodCode(
        byte[] bytes,
        ConstantPool pool,
        int classBodyOffset,
        int originalIndex,
        int captureRef,
        int originalVisibility,
        int visibilityRef
    ) throws IOException {
        int cursor = classBodyOffset + 6;
        int interfaces = readU2(bytes, cursor);
        cursor += 2 + interfaces * 2;
        int fields = readU2(bytes, cursor);
        cursor += 2;
        for (int index = 0; index < fields; index++) {
            cursor = skipMember(bytes, cursor);
        }

        int methods = readU2(bytes, cursor);
        cursor += 2;
        int patched = 0;
        for (int method = 0; method < methods; method++) {
            cursor += 2;
            int nameIndex = readU2(bytes, cursor);
            cursor += 2;
            cursor += 2;
            int attributes = readU2(bytes, cursor);
            cursor += 2;
            boolean targetMethod = TARGET_METHOD.equals(pool.utf8(nameIndex));
            for (int attribute = 0; attribute < attributes; attribute++) {
                int attributeName = readU2(bytes, cursor);
                int length = Math.toIntExact(readU4(bytes, cursor + 2));
                int content = cursor + 6;
                if (targetMethod && "Code".equals(pool.utf8(attributeName))) {
                    int codeLength = (int) readU4(bytes, content + 4);
                    int codeStart = content + 8;
                    int codeEnd = codeStart + codeLength;
                    for (int offset = codeStart; offset + 2 < codeEnd; offset++) {
                        int opcode = bytes[offset] & 0xFF;
                        int methodRef = readU2(bytes, offset + 1);
                        if (opcode == 0xB6 && methodRef == originalIndex) {
                            bytes[offset] = (byte) 0xB8;
                            writeU2(bytes, offset + 1, captureRef);
                            patched++;
                        } else if (opcode == 0xB6 && methodRef == originalVisibility) {
                            bytes[offset] = (byte) 0xB8;
                            writeU2(bytes, offset + 1, visibilityRef);
                            patched++;
                        }
                    }
                }
                cursor = content + length;
            }
        }
        return patched;
    }

    private static int skipMember(byte[] bytes, int cursor) {
        cursor += 6;
        int attributes = readU2(bytes, cursor);
        cursor += 2;
        for (int index = 0; index < attributes; index++) {
            cursor += 6 + Math.toIntExact(readU4(bytes, cursor + 2));
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
