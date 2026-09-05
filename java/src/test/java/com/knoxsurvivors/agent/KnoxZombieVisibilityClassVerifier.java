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
        try (ZipFile gameJar = new ZipFile(Path.of(arguments[0]).toFile())) {
            byte[] impact = gameJar.getInputStream(gameJar.getEntry("zombie/CombatManager.class")).readAllBytes();
            ClassLoader impactLoader = new PatchedIsoZombieLoader(
                KnoxZombieVisibilityClassVerifier.class.getClassLoader(), "zombie.CombatManager",
                KnoxSwipeStateTransformer.patchHumanForVerification(
                    KnoxSwipeStateTransformer.patchImpactForVerification(impact)));
            Class<?> impactClass = Class.forName("zombie.CombatManager", false, impactLoader);
            if (impactClass.getClassLoader() != impactLoader) throw new AssertionError("Impact patch not defined");
            java.lang.reflect.Field api = KnoxHumanCombatGate.class.getDeclaredField("API");
            api.setAccessible(true);
            ((ClassValue<?>) api.get(null)).get(Class.forName("zombie.characters.IsoPlayer", false,
                KnoxZombieVisibilityClassVerifier.class.getClassLoader()));
            System.out.println("human combat native reflection API verified without game initialization");
            System.out.println("combat impact transformed class verified runtime=" + Runtime.version().feature());
        }
        System.out.println("zombie visibility transformed class verified runtime="
            + Runtime.version().feature());
    }

    private static final class PatchedIsoZombieLoader extends ClassLoader {
        private final byte[] patched;
        private final String targetName;

        private PatchedIsoZombieLoader(ClassLoader parent, byte[] patched) {
            this(parent, TARGET_NAME, patched);
        }

        private PatchedIsoZombieLoader(ClassLoader parent, String targetName, byte[] patched) {
            super(parent);
            this.patched = patched;
            this.targetName = targetName;
        }

        @Override
        protected synchronized Class<?> loadClass(String name, boolean resolve)
            throws ClassNotFoundException {
            if (!targetName.equals(name)) {
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
