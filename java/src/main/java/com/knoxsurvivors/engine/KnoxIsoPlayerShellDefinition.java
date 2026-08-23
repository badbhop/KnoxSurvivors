package com.knoxsurvivors.engine;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.lang.invoke.MethodHandles;

/** Defines the minimal IsoPlayer subclass required by Build 42's exact-class render filter. */
public final class KnoxIsoPlayerShellDefinition {
    public static final String CLASS_NAME = "com.knoxsurvivors.engine.KnoxIsoPlayerShell";
    private static final String INTERNAL_NAME = "com/knoxsurvivors/engine/KnoxIsoPlayerShell";
    private static final String SUPER_INTERNAL_NAME = "zombie/characters/IsoPlayer";
    private static final String CONSTRUCTOR_DESCRIPTOR =
        "(Lzombie/iso/IsoCell;Lzombie/characters/SurvivorDesc;IIIZ)V";

    private static Class<?> definedClass;

    private KnoxIsoPlayerShellDefinition() {
    }

    public static synchronized Class<?> getOrDefine(ClassLoader gameClassLoader)
        throws ReflectiveOperationException {
        if (definedClass != null) {
            return definedClass;
        }

        try {
            definedClass = Class.forName(CLASS_NAME, false, gameClassLoader);
        } catch (ClassNotFoundException notDefinedYet) {
            try {
                definedClass = MethodHandles.lookup().defineClass(createClassBytes());
            } catch (IllegalAccessException | IOException exception) {
                throw new ReflectiveOperationException("Unable to define " + CLASS_NAME, exception);
            }
        }

        if (!"zombie.characters.IsoPlayer".equals(definedClass.getSuperclass().getName())) {
            throw new IllegalStateException(CLASS_NAME + " has an unexpected superclass");
        }
        return definedClass;
    }

    private static byte[] createClassBytes() throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (DataOutputStream output = new DataOutputStream(bytes)) {
            output.writeInt(0xCAFEBABE);
            output.writeShort(0);
            output.writeShort(61);

            output.writeShort(21);
            writeUtf8(output, INTERNAL_NAME);                 // 1
            writeClass(output, 1);                            // 2
            writeUtf8(output, SUPER_INTERNAL_NAME);           // 3
            writeClass(output, 3);                            // 4
            writeUtf8(output, "<init>");                     // 5
            writeUtf8(output, CONSTRUCTOR_DESCRIPTOR);        // 6
            writeNameAndType(output, 5, 6);                   // 7
            writeMethodRef(output, 4, 7);                     // 8
            writeUtf8(output, "Code");                       // 9
            writeUtf8(output, "getCharacterInputComponent"); // 10
            writeUtf8(
                output,
                "()Lzombie/characters/component/CharacterInputComponent;"
            );                                                 // 11
            writeUtf8(output, "isLocalPlayer");               // 12
            writeUtf8(output, "()Z");                         // 13
            writeUtf8(output, "getAimVector");                // 14
            writeUtf8(
                output,
                "(Lzombie/iso/Vector2;)Lzombie/iso/Vector2;"
            );                                                  // 15
            writeUtf8(output, "getForwardDirection");          // 16
            writeNameAndType(output, 16, 15);                   // 17
            writeMethodRef(output, 4, 17);                      // 18
            writeUtf8(output, "setAngleFromAim");              // 19
            writeUtf8(output, "()V");                          // 20

            output.writeShort(0x0021);
            output.writeShort(2);
            output.writeShort(4);
            output.writeShort(0);
            output.writeShort(0);
            output.writeShort(5);

            output.writeShort(0x0001);
            output.writeShort(5);
            output.writeShort(6);
            output.writeShort(1);
            output.writeShort(9);
            output.writeInt(26);
            output.writeShort(7);
            output.writeShort(7);
            output.writeInt(14);
            output.write(new byte[] {
                0x2A,
                0x2B,
                0x2C,
                0x1D,
                0x15, 0x04,
                0x15, 0x05,
                0x15, 0x06,
                (byte) 0xB7, 0x00, 0x08,
                (byte) 0xB1,
            });
            output.writeShort(0);
            output.writeShort(0);

            output.writeShort(0x0001);
            output.writeShort(10);
            output.writeShort(11);
            output.writeShort(1);
            output.writeShort(9);
            output.writeInt(14);
            output.writeShort(1);
            output.writeShort(1);
            output.writeInt(2);
            output.write(new byte[] { 0x01, (byte) 0xB0 });
            output.writeShort(0);
            output.writeShort(0);

            output.writeShort(0x0001);
            output.writeShort(12);
            output.writeShort(13);
            output.writeShort(1);
            output.writeShort(9);
            output.writeInt(14);
            output.writeShort(1);
            output.writeShort(1);
            output.writeInt(2);
            output.write(new byte[] { 0x03, (byte) 0xAC });
            output.writeShort(0);
            output.writeShort(0);

            // Off-slot NPCs have no mouse/controller input component. Supply the
            // already-controller-owned forward direction as their melee aim vector.
            output.writeShort(0x0001);
            output.writeShort(14);
            output.writeShort(15);
            output.writeShort(1);
            output.writeShort(9);
            output.writeInt(18);
            output.writeShort(2);
            output.writeShort(2);
            output.writeInt(6);
            output.write(new byte[] {
                0x2A,
                0x2B,
                (byte) 0xB6, 0x00, 0x12,
                (byte) 0xB0,
            });
            output.writeShort(0);
            output.writeShort(0);

            // The controller sets facing explicitly. The local-player implementation
            // would otherwise replace it with a missing mouse/controller aim source.
            output.writeShort(0x0001);
            output.writeShort(19);
            output.writeShort(20);
            output.writeShort(1);
            output.writeShort(9);
            output.writeInt(13);
            output.writeShort(0);
            output.writeShort(1);
            output.writeInt(1);
            output.writeByte(0xB1);
            output.writeShort(0);
            output.writeShort(0);

            output.writeShort(0);
        }
        return bytes.toByteArray();
    }

    private static void writeUtf8(DataOutputStream output, String value) throws IOException {
        output.writeByte(1);
        output.writeUTF(value);
    }

    private static void writeClass(DataOutputStream output, int nameIndex) throws IOException {
        output.writeByte(7);
        output.writeShort(nameIndex);
    }

    private static void writeNameAndType(DataOutputStream output, int nameIndex, int descriptorIndex)
        throws IOException {
        output.writeByte(12);
        output.writeShort(nameIndex);
        output.writeShort(descriptorIndex);
    }

    private static void writeMethodRef(DataOutputStream output, int classIndex, int nameAndTypeIndex)
        throws IOException {
        output.writeByte(10);
        output.writeShort(classIndex);
        output.writeShort(nameAndTypeIndex);
    }
}
