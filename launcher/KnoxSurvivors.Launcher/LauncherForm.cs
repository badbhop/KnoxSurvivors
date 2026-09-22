using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

namespace KnoxSurvivors.Launcher
{
    internal sealed class LauncherForm : Form
    {
        private readonly Label statusLabel;
        private readonly GradientLaunchButton launchButton;
        private readonly Panel bottomBar;
        private readonly SteamLocator locator = new SteamLocator();
        private readonly InstallationValidator validator = new InstallationValidator();
        private readonly GameLauncher gameLauncher = new GameLauncher();
        private readonly Image backgroundImage;
        private LauncherInstallation installation;

        public LauncherForm()
        {
            Text = "Knox Survivors";
            ClientSize = new Size(1280, 720);
            MinimumSize = Size;
            MaximumSize = Size;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(5, 6, 8);
            ForeColor = Color.White;
            Font = new Font("Segoe UI", 10.0f, FontStyle.Regular, GraphicsUnit.Point);
            AutoScaleMode = AutoScaleMode.Dpi;
            DoubleBuffered = true;
            ResizeRedraw = true;

            backgroundImage = TryLoadBackground();

            // Bottom scrim bar keeps status + launch readable over busy art
            // while leaving the artwork fully visible above. Future buttons
            // can dock into this same panel.
            bottomBar = new Panel
            {
                Dock = DockStyle.Bottom,
                Height = 168,
                BackColor = Color.FromArgb(178, 5, 6, 8),
            };
            statusLabel = new Label
            {
                AutoSize = false,
                Bounds = new Rectangle(140, 14, 1000, 44),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                Text = "Checking Steam Workshop...",
                ForeColor = Color.FromArgb(190, 194, 200),
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleCenter,
            };
            launchButton = new GradientLaunchButton
            {
                Bounds = new Rectangle(372, 64, 536, 82),
                Anchor = AnchorStyles.Top,
                Text = "LAUNCH",
                Enabled = false,
            };
            launchButton.Click += LaunchButtonOnClick;

            bottomBar.Controls.Add(statusLabel);
            bottomBar.Controls.Add(launchButton);
            Controls.Add(bottomBar);
            Shown += (sender, arguments) => RefreshInstallation();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && backgroundImage != null)
            {
                backgroundImage.Dispose();
            }
            base.Dispose(disposing);
        }

        private static Image TryLoadBackground()
        {
            // 1) Sidecar next to the exe (lets players/art swap without rebuild).
            // 2) Dev-time Assets folder.
            // 3) Embedded resource (offline single-exe builds).
            try
            {
                string baseDirectory = null;
                try { baseDirectory = AppDomain.CurrentDomain.BaseDirectory; } catch { }
                string[] candidates = baseDirectory != null
                    ? new[]
                    {
                        Path.Combine(baseDirectory, "background.png"),
                        Path.Combine(baseDirectory, "background.jpg"),
                        Path.Combine(baseDirectory, "background.jpeg"),
                        Path.Combine(baseDirectory, "Assets", "background.png"),
                        Path.Combine(baseDirectory, "Assets", "background.jpg"),
                    }
                    : new string[0];
                foreach (string path in candidates)
                {
                    try
                    {
                        if (!string.IsNullOrEmpty(path) && File.Exists(path))
                        {
                            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                            using (var loaded = Image.FromStream(stream))
                            {
                                return new Bitmap(loaded);
                            }
                        }
                    }
                    catch { }
                }

                string assemblyLocation = null;
                try { assemblyLocation = Assembly.GetExecutingAssembly().Location; } catch { }
                if (!string.IsNullOrEmpty(assemblyLocation))
                {
                    string assemblyDirectory = Path.GetDirectoryName(assemblyLocation);
                    if (!string.IsNullOrEmpty(assemblyDirectory))
                    {
                        string[] devCandidates =
                        {
                            Path.Combine(assemblyDirectory, "Assets", "background.png"),
                            Path.Combine(assemblyDirectory, "Assets", "background.jpg"),
                        };
                        foreach (string path in devCandidates)
                        {
                            try
                            {
                                if (File.Exists(path))
                                {
                                    using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                                    using (var loaded = Image.FromStream(stream))
                                    {
                                        return new Bitmap(loaded);
                                    }
                                }
                            }
                            catch { }
                        }
                    }
                }

                var assembly = Assembly.GetExecutingAssembly();
                string[] resourceNames = { "background.png", "background.jpg", "background.jpeg", "Assets.background.png" };
                foreach (string resourceName in assembly.GetManifestResourceNames())
                {
                    foreach (string wanted in resourceNames)
                    {
                        if (resourceName.EndsWith(wanted, StringComparison.OrdinalIgnoreCase))
                        {
                            try
                            {
                                using (var stream = assembly.GetManifestResourceStream(resourceName))
                                {
                                    if (stream != null)
                                    {
                                        using (var loaded = Image.FromStream(stream))
                                        {
                                            return new Bitmap(loaded);
                                        }
                                    }
                                }
                            }
                            catch { }
                        }
                    }
                }
            }
            catch { }
            return null;
        }

        protected override void OnPaint(PaintEventArgs arguments)
        {
            var graphics = arguments.Graphics;
            graphics.SmoothingMode = SmoothingMode.HighQuality;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.CompositingQuality = CompositingQuality.HighQuality;

            if (backgroundImage != null)
            {
                // Cover-fit: fill the window, center-crop overflow, never stretch.
                // This is what keeps the art sharp and undistorted at 1280x720.
                Rectangle client = ClientRectangle;
                float scale = Math.Max(
                    (float)client.Width / backgroundImage.Width,
                    (float)client.Height / backgroundImage.Height);
                int drawWidth = (int)Math.Ceiling(backgroundImage.Width * scale);
                int drawHeight = (int)Math.Ceiling(backgroundImage.Height * scale);
                int drawX = client.X + (client.Width - drawWidth) / 2;
                int drawY = client.Y + (client.Height - drawHeight) / 2;
                graphics.DrawImage(backgroundImage, new Rectangle(drawX, drawY, drawWidth, drawHeight));

                // Gentle top vignette so the window frame blends into dark art.
                using (var vignette = new LinearGradientBrush(
                    new Rectangle(0, 0, client.Width, 90),
                    Color.FromArgb(140, 0, 0, 0),
                    Color.FromArgb(0, 0, 0, 0),
                    LinearGradientMode.Vertical))
                {
                    graphics.FillRectangle(vignette, 0, 0, client.Width, 90);
                }
            }
            else
            {
                using (var fill = new SolidBrush(Color.FromArgb(5, 6, 8)))
                {
                    graphics.FillRectangle(fill, ClientRectangle);
                }
            }

            base.OnPaint(arguments);
            using (var border = new Pen(Color.FromArgb(90, 188, 255, 0), 1.0f))
            {
                graphics.DrawRectangle(border, 16, 16, ClientSize.Width - 33, ClientSize.Height - 33);
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
