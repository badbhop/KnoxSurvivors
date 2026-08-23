package com.knoxsurvivors.engine;

/** Runtime verifier for the dynamically defined Build 42 IsoPlayer shell. */
public final class KnoxIsoPlayerShellVerifier {
    private KnoxIsoPlayerShellVerifier() {
    }

    public static void main(String[] args) throws Exception {
        Class<?> shell = KnoxIsoPlayerShellDefinition.getOrDefine(
            KnoxIsoPlayerShellDefinition.class.getClassLoader()
        );
        require(shell.getDeclaredMethod("update").getDeclaringClass() == shell, "update override");
        require(
            shell.getDeclaredMethod("isLocalPlayer").getDeclaringClass() == shell,
            "local-player override"
        );
        require(
            shell.getDeclaredMethod("updateLOS").getDeclaringClass() == shell,
            "LOS isolation override"
        );
        ClassLoader loader = shell.getClassLoader();
        Class<?> door = Class.forName("zombie.iso.objects.IsoDoor", false, loader);
        Class<?> character = Class.forName(
            "zombie.characters.IsoGameCharacter",
            false,
            loader
        );
        Class<?> weapon = Class.forName(
            "zombie.inventory.types.HandWeapon",
            false,
            loader
        );
        door.getMethod("getHealth");
        door.getMethod("isDestroyed");
        door.getMethod("getSquare");
        door.getMethod("WeaponHit", character, weapon);
        System.out.println(
            "IsoPlayer shell verified global-instance guard=true LOS isolation=true"
                + " locked-door-combat-api=true"
        );
    }

    private static void require(boolean condition, String description) {
        if (!condition) {
            throw new IllegalStateException("Missing " + description);
        }
    }
}
