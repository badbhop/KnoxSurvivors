using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace KnoxSurvivors.Launcher
{
    internal sealed class LauncherForm : Form
    {
        private readonly Label statusLabel;
        private readonly GradientLaunchButton launchButton;
        private readonly SteamLocator locator = new SteamLocator();
        private readonly InstallationValidator validator = new InstallationValidator();
        private readonly GameLauncher gameLauncher = new GameLauncher();
        private LauncherInstallation installation;

        public LauncherForm()
        {
            Text = "Knox Survivors";
            ClientSize = new Size(720, 400);
            MinimumSize = Size;
            MaximumSize = Size;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(5, 6, 8);
            ForeColor = Color.White;
            Font = new Font("Segoe UI", 10.0f, FontStyle.Regular, GraphicsUnit.Point);

            var title = new Label
            {
                AutoSize = false,
                Bounds = new Rectangle(54, 54, 612, 58),
                Text = "KNOX SURVIVORS",
                Font = new Font("Segoe UI Semibold", 29.0f, FontStyle.Bold, GraphicsUnit.Point),
                ForeColor = Color.FromArgb(188, 255, 0),
                TextAlign = ContentAlignment.MiddleCenter,
            };
            var subtitle = new Label
            {
                AutoSize = false,
                Bounds = new Rectangle(54, 112, 612, 32),
                Text = "PROJECT ZOMBOID 42.20",
                Font = new Font("Segoe UI", 10.0f, FontStyle.Regular, GraphicsUnit.Point),
                ForeColor = Color.FromArgb(180, 150, 255),
                TextAlign = ContentAlignment.MiddleCenter,
            };
            statusLabel = new Label
            {
                AutoSize = false,
                Bounds = new Rectangle(70, 171, 580, 45),
                Text = "Checking Steam Workshop...",
                ForeColor = Color.FromArgb(190, 194, 200),
                TextAlign = ContentAlignment.MiddleCenter,
            };
            launchButton = new GradientLaunchButton
            {
                Bounds = new Rectangle(92, 246, 536, 82),
                Text = "LAUNCH",
                Enabled = false,
            };
            launchButton.Click += LaunchButtonOnClick;

            Controls.Add(title);
            Controls.Add(subtitle);
            Controls.Add(statusLabel);
            Controls.Add(launchButton);
            Shown += (sender, arguments) => RefreshInstallation();
        }

        protected override void OnPaint(PaintEventArgs arguments)
        {
            base.OnPaint(arguments);
            using (var border = new Pen(Color.FromArgb(90, 188, 255, 0), 1.0f))
            {
                arguments.Graphics.DrawRectangle(border, 16, 16, ClientSize.Width - 33, ClientSize.Height - 33);
            }
        }

        private void RefreshInstallation()
        {
            try
            {
                installation = locator.Locate();
                validator.Validate(installation);
                statusLabel.Text = "READY  •  Workshop files and Java runtime verified";
                statusLabel.ForeColor = Color.FromArgb(188, 255, 0);
                launchButton.Enabled = true;
            }
            catch (LauncherException exception)
            {
                installation = null;
                statusLabel.Text = exception.Message;
                statusLabel.ForeColor = Color.FromArgb(225, 100, 140);
                launchButton.Enabled = true;
            }
        }

        private void LaunchButtonOnClick(object sender, EventArgs arguments)
        {
            launchButton.Enabled = false;
            try
            {
                installation = locator.Locate();
                validator.Validate(installation);
                statusLabel.Text = "Launching Project Zomboid...";
                statusLabel.ForeColor = Color.FromArgb(188, 255, 0);
                gameLauncher.Launch(installation);
                Close();
            }
            catch (LauncherException exception)
            {
                statusLabel.Text = exception.Message;
                statusLabel.ForeColor = Color.FromArgb(225, 100, 140);
                MessageBox.Show(
                    exception.Message,
                    "Knox Survivors",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning
                );
                launchButton.Enabled = true;
            }
            catch (Exception exception)
            {
                const string message = "Project Zomboid could not be launched. Verify the game and Workshop item through Steam.";
                statusLabel.Text = message;
                statusLabel.ForeColor = Color.FromArgb(225, 100, 140);
                MessageBox.Show(
                    message + Environment.NewLine + Environment.NewLine + exception.Message,
                    "Knox Survivors",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
                launchButton.Enabled = true;
            }
        }
    }

    internal sealed class GradientLaunchButton : Button
    {
        public GradientLaunchButton()
        {
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            Cursor = Cursors.Hand;
            Font = new Font("Segoe UI Semibold", 23.0f, FontStyle.Bold, GraphicsUnit.Point);
            ForeColor = Color.FromArgb(4, 5, 6);
        }

        protected override void OnPaint(PaintEventArgs arguments)
        {
            arguments.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle area = ClientRectangle;
            if (area.Width <= 0 || area.Height <= 0)
            {
                return;
            }
            Color left = Enabled ? Color.FromArgb(188, 255, 0) : Color.FromArgb(80, 92, 55);
            Color right = Enabled ? Color.FromArgb(162, 55, 255) : Color.FromArgb(75, 55, 86);
            using (var background = new LinearGradientBrush(area, left, right, 0.0f))
            using (var border = new Pen(Color.FromArgb(220, 205, 255, 105), 2.0f))
            {
                arguments.Graphics.FillRectangle(background, area);
                arguments.Graphics.DrawRectangle(border, 1, 1, area.Width - 3, area.Height - 3);
            }
            TextRenderer.DrawText(
                arguments.Graphics,
                Text,
                Font,
                area,
                ForeColor,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter
            );
        }
    }
}
