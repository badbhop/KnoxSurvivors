using System;
using System.Threading;
using System.Windows.Forms;

namespace KnoxSurvivors.Launcher
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            bool ownsMutex;
            using (var mutex = new Mutex(true, "Local\\KnoxSurvivorsLauncher", out ownsMutex))
            {
                if (!ownsMutex)
                {
                    MessageBox.Show(
                        "The Knox Survivors launcher is already open.",
                        "Knox Survivors",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Information
                    );
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new LauncherForm());
            }
        }
    }
}
