using KnoxSurvivors.Launcher;
using System;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;

namespace KnoxSurvivors.Launcher.Verifier
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] arguments)
        {
            string temporaryRoot = Path.Combine(
                Path.GetTempPath(),
                "Knox Launcher Verify " + Guid.NewGuid().ToString("N")
            );
            try
            {
                Directory.CreateDirectory(temporaryRoot);
                VerifyLibraryParsing(temporaryRoot);
                VerifyInstallationAndLaunchPlan(temporaryRoot);
                if (arguments.Length == 1)
                {
                    RenderPreview(arguments[0]);
                }
                Console.WriteLine("launcher verification passed");
                return 0;
            }
            finally
            {
                if (Directory.Exists(temporaryRoot))
                {
                    Directory.Delete(temporaryRoot, true);
                }
            }
        }

        private static void VerifyLibraryParsing(string root)
        {
            string steam = Path.Combine(root, "Steam");
            string second = Path.Combine(root, "Second Library");
            Directory.CreateDirectory(Path.Combine(steam, "steamapps"));
            string escaped = second.Replace("\\", "\\\\");
            File.WriteAllText(
                Path.Combine(steam, "steamapps", "libraryfolders.vdf"),
                "\"libraryfolders\"\n{\n  \"1\"\n  {\n    \"path\"  \"" + escaped + "\"\n  }\n}"
            );
            var libraries = SteamLocator.FindLibraries(steam);
            Require(libraries.Any(path => SamePath(path, steam)), "Primary Steam library missing");
            Require(libraries.Any(path => SamePath(path, second)), "Secondary Steam library missing");
        }

        private static void VerifyInstallationAndLaunchPlan(string root)
        {
            string game = Path.Combine(root, "ProjectZomboid");
            string workshop = Path.Combine(root, "3749727604");
            string mod = Path.Combine(workshop, "Contents", "mods", "KnoxSurvivors");
            string jar = Path.Combine(workshop, "java", "build", "libs", "knox-agent-test.jar");
            Directory.CreateDirectory(Path.Combine(game, "jre64", "bin"));
            Directory.CreateDirectory(Path.Combine(mod, "42"));
            Directory.CreateDirectory(Path.GetDirectoryName(jar));
            File.WriteAllText(Path.Combine(game, "ProjectZomboid64.bat"), "@echo off");
            File.WriteAllText(Path.Combine(mod, "mod.info"), "name=Knox Survivors\nid=KnoxSurvivors\n");
            File.WriteAllText(Path.Combine(mod, "42", "mod.info"), "name=Knox Survivors\nid=KnoxSurvivors\n");
            CreateAgentJar(jar);
            WriteChecksum(jar);

            var installation = new LauncherInstallation
            {
                GameDirectory = game,
                WorkshopItemDirectory = workshop,
                ModDirectory = mod,
                AgentJarPath = jar,
                GameBatchPath = Path.Combine(game, "ProjectZomboid64.bat"),
            };
            new InstallationValidator().Validate(installation);
            string previousJavaToolOptions = Environment.GetEnvironmentVariable("JAVA_TOOL_OPTIONS");
            Environment.SetEnvironmentVariable("JAVA_TOOL_OPTIONS", "-agentlib:zbNative -Xmx2G");
            GameLaunchPlan plan = new GameLauncher().CreatePlan(installation);
            Environment.SetEnvironmentVariable("JAVA_TOOL_OPTIONS", previousJavaToolOptions);
            Require(plan.WorkingDirectory == game, "Game working directory changed");
            Require(plan.Arguments.Contains(installation.GameBatchPath), "Game batch path missing");
            Require(plan.JavaToolOptions.Contains(installation.AgentJarPath), "Agent path missing");
            Require(plan.JavaToolOptions.EndsWith("=pz-game", StringComparison.Ordinal), "Agent mode missing");
            Require(plan.JavaToolOptions.Contains("-agentlib:zbNative"), "Existing agent option was not preserved");
            Require(plan.JavaToolOptions.Contains("-Xmx2G"), "Existing JVM option was not preserved");
            string agentOption = "-javaagent:\"" + installation.AgentJarPath + "\"=pz-game";
            string duplicate = GameLauncher.MergeJavaToolOptions(agentOption, agentOption);
            Require(
                duplicate.Split(new[] { "=pz-game" }, StringSplitOptions.None).Length == 2,
                "Knox agent option was duplicated"
            );

            string marker = Path.Combine(root, "launch-environment.txt");
            File.WriteAllText(
                installation.GameBatchPath,
                "@echo off\r\necho %JAVA_TOOL_OPTIONS% > \"" + marker + "\"\r\n"
            );
            new GameLauncher().Launch(installation);
            for (int attempt = 0; attempt < 40 && !File.Exists(marker); attempt++)
            {
                Thread.Sleep(50);
            }
            Require(File.Exists(marker), "Game batch was not started");
            string launchedOptions = File.ReadAllText(marker);
            Require(launchedOptions.Contains(installation.AgentJarPath), "Child process lost agent path");
            Require(launchedOptions.Contains("=pz-game"), "Child process lost agent mode");
        }

        private static void CreateAgentJar(string path)
        {
            using (ZipArchive archive = ZipFile.Open(path, ZipArchiveMode.Create))
            {
                ZipArchiveEntry manifest = archive.CreateEntry("META-INF/MANIFEST.MF");
                using (var writer = new StreamWriter(manifest.Open()))
                {
                    writer.WriteLine("Manifest-Version: 1.0");
                    writer.WriteLine("Premain-Class: com.knoxsurvivors.agent.KnoxAgent");
                }
                ZipArchiveEntry padding = archive.CreateEntry("verification-padding.bin");
                using (Stream stream = padding.Open())
                {
                    var random = new Random(42);
                    byte[] bytes = new byte[4096];
                    random.NextBytes(bytes);
                    stream.Write(bytes, 0, bytes.Length);
                }
            }
        }

        private static void WriteChecksum(string path)
        {
            string hash;
            using (SHA256 sha256 = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                hash = BitConverter.ToString(sha256.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
            }
            File.WriteAllText(path + ".sha256", hash + "  " + Path.GetFileName(path) + Environment.NewLine);
        }

        private static void RenderPreview(string outputPath)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using (var form = new LauncherForm())
            {
                form.Show();
                Application.DoEvents();
                using (var bitmap = new Bitmap(form.Width, form.Height))
                {
                    form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size));
                    Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath)));
                    bitmap.Save(outputPath, System.Drawing.Imaging.ImageFormat.Png);
                }
                form.Close();
            }
        }

        private static bool SamePath(string first, string second)
        {
            return string.Equals(
                Path.GetFullPath(first).TrimEnd(Path.DirectorySeparatorChar),
                Path.GetFullPath(second).TrimEnd(Path.DirectorySeparatorChar),
                StringComparison.OrdinalIgnoreCase
            );
        }

        private static void Require(bool condition, string message)
        {
            if (!condition)
            {
                throw new InvalidOperationException(message);
            }
        }
    }
}
