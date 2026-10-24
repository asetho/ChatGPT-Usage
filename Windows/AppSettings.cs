using Microsoft.Win32;
using System.IO;

namespace ChatGPTUsage.Windows;

internal static class AppSettings
{
    private const string SettingsPath = @"Software\asetho\ChatGPT Usage";
    private const string RunPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string StartupApprovalPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
    private const string StartupName = "ChatGPT Usage";

    public static string? CodexExecutablePath
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(SettingsPath);
                return key?.GetValue("CodexExecutablePath") as string;
            }
            catch { return null; }
        }
    }

    public static bool LaunchAtLogin
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunPath);
            return key?.GetValue(StartupName) is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunPath);
            if (value)
            {
                var executable = Environment.ProcessPath ?? throw new InvalidOperationException("Could not locate this app.");
                key.SetValue(StartupName, $"\"{executable}\"", RegistryValueKind.String);
            }
            else key.DeleteValue(StartupName, throwOnMissingValue: false);
        }
    }

    public static bool StartupDisabledByWindows
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(StartupApprovalPath);
            return key?.GetValue(StartupName) is byte[] { Length: > 0 } approval && (approval[0] & 1) != 0;
        }
    }

    public static void SelectExecutable(string? path)
    {
        if (path is not null && (!File.Exists(path) ||
            !(Path.GetExtension(path).Equals(".exe", StringComparison.OrdinalIgnoreCase) ||
              Path.GetExtension(path).Equals(".cmd", StringComparison.OrdinalIgnoreCase))))
            throw new InvalidOperationException("Choose a Codex .exe or .cmd executable.");

        using var key = Registry.CurrentUser.CreateSubKey(SettingsPath);
        if (path is null) key.DeleteValue("CodexExecutablePath", throwOnMissingValue: false);
        else key.SetValue("CodexExecutablePath", path, RegistryValueKind.String);
    }
}
