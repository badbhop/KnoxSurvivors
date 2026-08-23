using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace KnoxSurvivors.Launcher
{
    internal sealed class SteamLocator
    {
        internal const string SteamAppId = "108600";
        internal const string WorkshopItemId = "3749727604";

        public LauncherInstallation Locate()
        {
            string steamDirectory = FindSteamDirectory();
            if (steamDirectory == null)
            {
                throw new LauncherException(
                    "Steam could not be found. Install Steam and Project Zomboid, then try again."
                );
            }

            IReadOnlyList<string> libraries = FindLibraries(steamDirectory);
            string gameDirectory = libraries
                .Select(path => Path.Combine(path, "steamapps", "common", "ProjectZomboid"))
                .FirstOrDefault(IsGameDirectory);
            if (gameDirectory == null)
            {
                throw new LauncherException(
                    "Project Zomboid was not found in any Steam library. Install it through Steam first."
                );
            }

            string workshopDirectory = libraries
                .Select(path => Path.Combine(
                    path,
                    "steamapps",
                    "workshop",
                    "content",
                    SteamAppId,
                    WorkshopItemId
                ))
                .FirstOrDefault(Directory.Exists);
            if (workshopDirectory == null)
            {
                throw new LauncherException(
                    "Knox Survivors is not installed by Steam Workshop yet. Subscribe to Workshop item "
                        + WorkshopItemId
                        + ", let Steam finish downloading it, then press Launch again."
                );
            }

            string modDirectory = Path.Combine(
                workshopDirectory,
                "Contents",
                "mods",
                "KnoxSurvivors"
            );
            string agentDirectory = Path.Combine(workshopDirectory, "java", "build", "libs");
            string[] agentJars = Directory.Exists(agentDirectory)
                ? Directory.GetFiles(agentDirectory, "knox-agent-*.jar", SearchOption.TopDirectoryOnly)
                : Array.Empty<string>();
            if (agentJars.Length != 1)
            {
                throw new LauncherException(
                    agentJars.Length == 0
                        ? "The Workshop download is missing the Knox Java runtime. Let Steam verify the item and try again."
                        : "The Workshop download contains multiple Knox Java runtimes. Verify the item through Steam and try again."
                );
            }

            return new LauncherInstallation
            {
                SteamDirectory = steamDirectory,
                GameDirectory = gameDirectory,
                WorkshopItemDirectory = workshopDirectory,
                ModDirectory = modDirectory,
                AgentJarPath = agentJars[0],
                GameBatchPath = Path.Combine(gameDirectory, "ProjectZomboid64.bat"),
            };
        }

        internal static IReadOnlyList<string> FindLibraries(string steamDirectory)
        {
            var libraries = new List<string> { Normalize(steamDirectory) };
            string libraryFile = Path.Combine(steamDirectory, "steamapps", "libraryfolders.vdf");
            if (File.Exists(libraryFile))
            {
                string text = File.ReadAllText(libraryFile);
                foreach (Match match in Regex.Matches(
                    text,
                    "\\\"path\\\"\\s+\\\"(?<path>[^\\\"]+)\\\"",
                    RegexOptions.CultureInvariant
                ))
                {
                    string path = match.Groups["path"].Value.Replace("\\\\", "\\");
                    if (!string.IsNullOrWhiteSpace(path))
                    {
                        libraries.Add(Normalize(path));
                    }
                }
            }
            return libraries.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        }

        private static string FindSteamDirectory()
        {
            string path = ReadRegistryString(Registry.CurrentUser, @"Software\Valve\Steam", "SteamPath")
                ?? ReadRegistryString(
                    Registry.LocalMachine,
                    @"SOFTWARE\WOW6432Node\Valve\Steam",
                    "InstallPath"
                );
            return string.IsNullOrWhiteSpace(path) ? null : Normalize(path);
        }

        private static string ReadRegistryString(RegistryKey root, string subKey, string valueName)
        {
            using (RegistryKey key = root.OpenSubKey(subKey, false))
            {
                return key?.GetValue(valueName) as string;
            }
        }

        private static bool IsGameDirectory(string directory)
        {
            return Directory.Exists(directory)
                && File.Exists(Path.Combine(directory, "ProjectZomboid64.bat"))
                && File.Exists(Path.Combine(directory, "projectzomboid.jar"))
                && File.Exists(Path.Combine(directory, "jre64", "bin", "java.exe"));
        }

        private static string Normalize(string path)
        {
            return Path.GetFullPath(path.Replace('/', Path.DirectorySeparatorChar));
        }
    }
}
