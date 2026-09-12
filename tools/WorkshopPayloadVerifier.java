import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.jar.JarFile;

/** Read-only upload-layout check against the installed game's own Workshop validator. */
public final class WorkshopPayloadVerifier {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("Expected Workshop staging folder");
        Path root = Path.of(args[0]).toAbsolutePath().normalize();
        if (!Files.isDirectory(root)) throw new IllegalArgumentException("Staging folder missing: " + root);
        Class<?> type = Class.forName("zombie.core.znet.SteamWorkshopItem");
        // Seed only the native path validator's base directory, without booting
        // the game, Steam, a world, or the full filesystem/mod loader.
        Class<?> filesystem = Class.forName("zombie.ZomboidFileSystem");
        Object instance = filesystem.getField("instance").get(null);
        // This standalone verifier owns no game session. Use the existing
        // candidate root as its process-local cache so native prefix validation
        // also accepts isolated build directories, without touching player saves.
        filesystem.getMethod("setCacheDir", String.class).invoke(instance, root.toString());
        Object base = filesystem.getField("base").get(instance);
        Path game = Path.of(type.getProtectionDomain().getCodeSource().getLocation().toURI()).getParent();
        base.getClass().getMethod("set", java.io.File.class).invoke(base, game.toFile());
        Object item = type.getConstructor(String.class).newInstance(root.toString());
        Path uploaded = Path.of((String) type.getMethod("getContentFolder").invoke(item));
        if (!uploaded.equals(root.resolve("Contents"))) throw new IllegalStateException("Unexpected native upload root");
        for (String name : new String[] { "validateModsFolder", "validateFileTypes" }) {
            Method method = type.getDeclaredMethod(name, Path.class);
            method.setAccessible(true);
            Object error = method.invoke(item, name.equals("validateModsFolder") ? uploaded.resolve("mods") : uploaded);
            if (error != null) throw new IllegalStateException(name + ": " + error);
        }
        try (var files = Files.walk(uploaded)) {
            var jars = files.filter(Files::isRegularFile)
                .filter(path -> path.getFileName().toString().matches("knox-agent-.*\\.jar")).toList();
            if (jars.size() != 1) throw new IllegalStateException("Expected exactly one uploaded agent, got " + jars.size());
            Path jar = jars.get(0);
            String digest = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(Files.readAllBytes(jar)));
            String sidecar = Files.readString(jar.resolveSibling(jar.getFileName() + ".sha256")).trim();
            if (!sidecar.equals(digest + "  " + jar.getFileName())) {
                throw new IllegalStateException("Agent checksum mismatch: " + jar.getFileName());
            }
            try (JarFile archive = new JarFile(jar.toFile())) {
                if (archive.getManifest() == null || !"com.knoxsurvivors.agent.KnoxAgent".equals(
                    archive.getManifest().getMainAttributes().getValue("Premain-Class"))) {
                    throw new IllegalStateException("Agent premain manifest missing or invalid");
                }
            }
        }
        System.out.println("Native Workshop payload validation passed (Contents root, mod layout, file types, one agent, checksum and premain).");
        if (Files.exists(root.resolve("workshop.txt"))) {
            String metadata = Files.readString(root.resolve("workshop.txt"));
            if (!metadata.lines().anyMatch("id=3749727604"::equals)) {
                throw new IllegalStateException("Upload must update existing item 3749727604");
            }
            if (!Boolean.TRUE.equals(type.getMethod("readWorkshopTxt").invoke(item))
                || !"3749727604".equals(type.getMethod("getID").invoke(item))) {
                throw new IllegalStateException("Native uploader did not read existing item ID");
            }
            String description = (String) type.getMethod("getDescription").invoke(item);
            if (!description.contains("\uD83E\uDDDF") || !description.contains("KnoxSurvivorsLauncher/releases")) {
                throw new IllegalStateException("Native description decoding lost artwork heading or launcher link");
            }
            Object error = type.getMethod("validateContents").invoke(item);
            if (error != null) throw new IllegalStateException("Native upload validation: " + error);
            System.out.println("Native full upload validation passed, including preview; existing item ID confirmed.");
        } else {
            System.out.println("Upload metadata/preview still need preparation.");
        }
        System.out.println("Steam publication and subscribed-install gameplay remain separate live checks.");
    }
}
