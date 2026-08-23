using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;

namespace KnoxSurvivors.Launcher
{
    internal sealed class InstallationValidator
    {
        public void Validate(LauncherInstallation installation)
        {
            if (!File.Exists(installation.GameBatchPath))
            {
                throw new LauncherException("ProjectZomboid64.bat is missing. Verify Project Zomboid through Steam.");
            }

            string modInfo = Path.Combine(installation.ModDirectory, "mod.info");
            string build42ModInfo = Path.Combine(installation.ModDirectory, "42", "mod.info");
            if (!HasModId(modInfo) || !HasModId(build42ModInfo))
            {
                throw new LauncherException(
                    "The Workshop item does not contain the expected KnoxSurvivors Build 42 mod files."
                );
            }

            ValidateAgentJar(installation.AgentJarPath);
            ValidateAgentChecksum(installation.AgentJarPath);
        }

        private static bool HasModId(string path)
        {
            return File.Exists(path)
                && File.ReadAllLines(path).Any(
                    line => string.Equals(line.Trim(), "id=KnoxSurvivors", StringComparison.Ordinal)
                );
        }

        private static void ValidateAgentJar(string path)
        {
            if (!File.Exists(path) || new FileInfo(path).Length < 1024)
            {
                throw new LauncherException("The Knox Java runtime is missing or incomplete.");
            }

            try
            {
                using (var archive = ZipFile.OpenRead(path))
                {
                    ZipArchiveEntry manifest = archive.GetEntry("META-INF/MANIFEST.MF");
                    if (manifest == null)
                    {
                        throw new LauncherException("The Knox Java runtime has no manifest.");
                    }
                    string contents;
                    using (var reader = new StreamReader(manifest.Open()))
                    {
                        contents = reader.ReadToEnd();
                    }
                    if (contents.IndexOf(
                        "Premain-Class: com.knoxsurvivors.agent.KnoxAgent",
                        StringComparison.Ordinal
                    ) < 0)
                    {
                        throw new LauncherException("The Workshop Java runtime is not a Knox Survivors agent.");
                    }
                }
            }
            catch (InvalidDataException exception)
            {
                throw new LauncherException("The Knox Java runtime is damaged.", exception);
            }
        }

        private static void ValidateAgentChecksum(string jarPath)
        {
            string checksumPath = jarPath + ".sha256";
            if (!File.Exists(checksumPath))
            {
                throw new LauncherException("The Workshop Java runtime checksum is missing.");
            }
            string expected = File.ReadAllText(checksumPath).Trim().Split((char[]) null, 2)[0];
            if (expected.Length != 64 || expected.Any(character => !Uri.IsHexDigit(character)))
            {
                throw new LauncherException("The Workshop Java runtime checksum is invalid.");
            }
            string actual;
            using (SHA256 sha256 = SHA256.Create())
            using (FileStream stream = File.OpenRead(jarPath))
            {
                actual = BitConverter.ToString(sha256.ComputeHash(stream)).Replace("-", "");
            }
            if (!string.Equals(expected, actual, StringComparison.OrdinalIgnoreCase))
            {
                throw new LauncherException(
                    "The Knox Java runtime did not pass its integrity check. Verify the Workshop item through Steam."
                );
            }
        }
    }
}
