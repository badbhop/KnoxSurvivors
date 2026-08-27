package com.knoxsurvivors.agent;

import java.nio.file.Path;
import java.util.zip.ZipFile;

/**
 * Java 25-only verification that the transformed Build 42 IsoZombie class can be defined by
 * the same classfile runtime the game ships with. It intentionally does not initialize the
 * class or execute game code.
 */
public final class KnoxZombieVisibilityClassVerifier {
    private static final String TARGET_NAME = "zombie.characters.IsoZombie";
    private static final String TARGET_ENTRY = "zombie/characters/IsoZombie.class";

    private KnoxZombieVisibilityClassVerifier() {
    }

    public static void main(String[] arguments) throws Exception {
        if (Runtime.version().feature() < 25) {
            throw new IllegalStateException("This verifier must run on the Project Zomboid Java 25 runtime");
        }
        if (arguments.length != 1) {
            throw new IllegalArgumentException("Expected the Project Zomboid jar path");
        }
        byte[] original;
        try (ZipFile gameJar = new ZipFile(Path.of(arguments[0]).toFile())) {
            original = gameJar.getInputStream(gameJar.getEntry(TARGET_ENTRY)).readAllBytes();
        }
        byte[] patched = KnoxZombieVisibilityTransformer.patchForVerification(original);
        ClassLoader verifierLoader = new PatchedIsoZombieLoader(
            KnoxZombieVisibilityClassVerifier.class.getClassLoader(),
            patched
        );
        Class<?> defined = Class.forName(TARGET_NAME, false, verifierLoader);
        if (defined.getClassLoader() != verifierLoader) {
            throw new AssertionError("Patched IsoZombie was not defined by the verifier loader");
        }
        System.out.println("zombie visibility transformed class verified runtime="
            + Runtime.version().feature());
    }

    private static final class PatchedIsoZombieLoader extends ClassLoader {
        private final byte[] patched;

        private PatchedIsoZombieLoader(ClassLoader parent, byte[] patched) {
            super(parent);
            this.patched = patched;
        }

        @Override
        protected synchronized Class<?> loadClass(String name, boolean resolve)
            throws ClassNotFoundException {
            if (!TARGET_NAME.equals(name)) {
                return super.loadClass(name, resolve);
            }
            Class<?> alreadyLoaded = findLoadedClass(name);
            if (alreadyLoaded == null) {
                alreadyLoaded = defineClass(name, patched, 0, patched.length);
            }
            if (resolve) {
                resolveClass(alreadyLoaded);
            }
            return alreadyLoaded;
        }
    }
}
