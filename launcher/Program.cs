using System.Diagnostics;
using System.Runtime.InteropServices;

namespace EcoPulse.Launcher;

// Masaustu kisayolunun hedefi. Yerel API'yi acar, sonra Flutter penceresini baslatir.
internal static class Program
{
    private const string WindowTitle = "EcoPulse OSB";

    [STAThread]
    private static async Task Main()
    {
        try
        {
            string root = RepoRoot();
            string apiExe = Path.Combine(root, "api", "bin", "Debug", "net9.0", "EcoPulse.Api.exe");
            string? appExe = FirstExisting(
                Path.Combine(root, "app", "build", "windows", "x64", "runner", "Release", "ecopulse.exe"),
                Path.Combine(root, "app", "build", "windows", "x64", "runner", "Debug", "ecopulse.exe"));

            if (!File.Exists(apiExe) || appExe is null)
            {
                Native.MessageBox(IntPtr.Zero,
                    "EcoPulse henüz derlenmemiş. Masaüstündeki EcoPulse kısayolunu bir kez çalıştırın.",
                    WindowTitle,
                    0x00000030);
                return;
            }

            // API'yi uygulamayi one getirmeden once dogrula; acik istemci API'yi kullanmaya devam edebilir.
            // API ayaktaysa yeniden baslatma; degilse arka planda ac.
            if (!await HealthOk())
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = apiExe,
                    WorkingDirectory = Path.GetDirectoryName(apiExe)!,
                    UseShellExecute = false,
                    CreateNoWindow = true
                });
                if (!await WaitForHealth())
                {
                    Native.MessageBox(IntPtr.Zero,
                        "Yerel API açılmadı. 5080 portu meşgul olabilir.",
                        WindowTitle,
                        0x00000010);
                    return;
                }
            }

            Process? running = Process.GetProcessesByName("ecopulse")
                .FirstOrDefault(process => process.MainWindowHandle != IntPtr.Zero);
            if (running is not null)
            {
                Native.ShowWindow(running.MainWindowHandle, 9);
                Native.SetForegroundWindow(running.MainWindowHandle);
                return;
            }

            Process.Start(new ProcessStartInfo
            {
                FileName = appExe,
                WorkingDirectory = Path.GetDirectoryName(appExe)!,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            Native.MessageBox(IntPtr.Zero, ex.Message, WindowTitle, 0x00000010);
        }
    }

    // Launcher bin klasorunden yukari cikarak depo kokunu bulur.
    private static string RepoRoot()
    {
        DirectoryInfo? dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            bool found = File.Exists(Path.Combine(dir.FullName, "api", "EcoPulse.Api.csproj"))
                && File.Exists(Path.Combine(dir.FullName, "app", "pubspec.yaml"));
            if (found)
            {
                return dir.FullName;
            }

            dir = dir.Parent;
        }

        throw new InvalidOperationException("EcoPulse klasörü bulunamadı.");
    }

    private static string? FirstExisting(params string[] paths) => paths.FirstOrDefault(File.Exists);

    private static async Task<bool> HealthOk()
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
            using HttpResponseMessage response = await client.GetAsync("http://127.0.0.1:5080/health");
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    private static async Task<bool> WaitForHealth()
    {
        for (int attempt = 0; attempt < 40; attempt++)
        {
            if (await HealthOk())
            {
                return true;
            }

            await Task.Delay(250);
        }

        return false;
    }
}

internal static partial class Native
{
    [DllImport("user32.dll")]
    internal static extern bool SetForegroundWindow(IntPtr handle);

    [DllImport("user32.dll")]
    internal static extern bool ShowWindow(IntPtr handle, int command);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int MessageBox(IntPtr handle, string text, string caption, uint type);
}
