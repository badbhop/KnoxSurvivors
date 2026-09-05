using System;
using System.Diagnostics;
using System.IO;

namespace KnoxSurvivors.Launcher
{
    internal sealed class GameLaunchPlan
    {
        public string CommandInterpreter { get; set; }

        public string Arguments { get; set; }

        public string WorkingDirectory { get; set; }

        public string JavaToolOptions { get; set; }
    }

    internal sealed class GameLauncher
    {
        public GameLaunchPlan CreatePlan(LauncherInstallation installation)
        {
            string commandInterpreter = Environment.GetEnvironmentVariable("ComSpec");
            if (string.IsNullOrWhiteSpace(commandInterpreter))
            {
                commandInterpreter = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "cmd.exe"
                );
            }
            string agentOption = "-javaagent:\"" + installation.AgentJarPath + "\"=pz-game";
            string existingOptions = Environment.GetEnvironmentVariable("JAVA_TOOL_OPTIONS");

            return new GameLaunchPlan
            {
                CommandInterpreter = commandInterpreter,
                Arguments = "/d /s /c \"\"" + installation.GameBatchPath + "\"\"",
                WorkingDirectory = installation.GameDirectory,
                JavaToolOptions = MergeJavaToolOptions(existingOptions, agentOption),
            };
        }

        internal static string MergeJavaToolOptions(string existingOptions, string knoxOption)
        {
            string existing = (existingOptions ?? string.Empty).Trim();
            if (string.IsNullOrWhiteSpace(existing))
            {
                return knoxOption;
            }

            // Keep options supplied by Steam, the game batch file, or other
            // compatible agents (for example -agentlib:zbNative).  Only add
            // Knox when this exact option is not already present.
            if (existing.IndexOf(knoxOption, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return existing;
            }
            return existing + " " + knoxOption;
        }

        public void Launch(LauncherInstallation installation)
        {
            GameLaunchPlan plan = CreatePlan(installation);
            var startInfo = new ProcessStartInfo
            {
                FileName = plan.CommandInterpreter,
                Arguments = plan.Arguments,
                WorkingDirectory = plan.WorkingDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardInput = true,
            };
            startInfo.EnvironmentVariables["JAVA_TOOL_OPTIONS"] = plan.JavaToolOptions;
            Process process = Process.Start(startInfo);
            if (process == null)
            {
                throw new LauncherException("Windows did not start Project Zomboid.");
            }
            process.StandardInput.Close();
        }
    }
}
