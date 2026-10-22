using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;

namespace ChatGPTUsage.Windows;

internal static class UpdateInstaller
{
    internal const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\{85D35CB7-34B0-4D09-9E6F-8E4AE03AFAFA}_is1";
    private static string StateDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "asetho", "ChatGPT Usage", "Updates");
    private static string ErrorPath => Path.Combine(StateDirectory, "last-error.txt");

    public static string? TakePreviousError()
    {
        try
        {
            if (!File.Exists(ErrorPath)) return null;
            var message = File.ReadAllText(ErrorPath);
            File.Delete(ErrorPath);
            return message.Trim();
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    [SupportedOSPlatform("windows")]
    public static async Task PrepareAndLaunchAsync(AvailableUpdateInfo update, Action<string> status)
    {
        var package = update.Package ?? throw new InvalidOperationException("Use View release to install this update.");
        var installDirectory = GetInstallDirectory();
        Directory.CreateDirectory(StateDirectory);
        var transaction = Path.Combine(StateDirectory, "transaction-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(transaction);
        var handedOff = false;
        try
        {
            status("Downloading update…");
            var installer = await DownloadAsync(package.Installer, transaction);
            var checksum = await DownloadAsync(package.Checksum, transaction);
            status("Verifying update…");
            VerifyChecksumFile(await File.ReadAllTextAsync(checksum), package.Installer);

            using var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("ChatGPTUsage.InstallUpdate.ps1")
                ?? throw new InvalidOperationException("The update helper is missing. Use View release to install this update.");
            using var reader = new StreamReader(resource);
            var script = await reader.ReadToEndAsync();
            var scriptPath = Path.Combine(transaction, "InstallUpdate.ps1");
            await File.WriteAllTextAsync(scriptPath, script, new UTF8Encoding(false));
            var manifest = Path.Combine(transaction, "update.json");
            using var parent = Process.GetCurrentProcess();
            await File.WriteAllTextAsync(manifest, JsonSerializer.Serialize(new
            {
                ParentId = Environment.ProcessId,
                ParentStartTicks = parent.StartTime.ToUniversalTime().Ticks.ToString(),
                InstallDirectory = installDirectory,
                Installer = installer,
                Sha256 = package.Installer.Sha256,
                Version = update.Version,
                ErrorPath,
                Transaction = transaction
            }));
            // Encode only a fixed, bundled helper and a separately encoded local manifest path.
            // No release metadata is inserted into PowerShell source; execution policy is unchanged.
            var encodedPath = Convert.ToBase64String(Encoding.UTF8.GetBytes(manifest));
            var command = "& {\n" + script + "\n} -ManifestPath ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + encodedPath + "')))";
            var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"))
            {
                UseShellExecute = false,
                CreateNoWindow = true
            };
            foreach (var argument in new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", Convert.ToBase64String(Encoding.Unicode.GetBytes(command)) })
                start.ArgumentList.Add(argument);
            using var helper = Process.Start(start) ?? throw new IOException("The update helper couldn’t start.");
            var ready = Path.Combine(transaction, "ready");
            for (var attempt = 0; attempt < 150 && !File.Exists(ready); attempt++)
            {
                if (helper.HasExited) throw new IOException("The update helper couldn’t start.");
                await Task.Delay(100);
            }
            if (!File.Exists(ready))
            {
                if (!helper.HasExited) helper.Kill();
                throw new IOException("The update helper didn’t become ready. Try again.");
            }
            handedOff = true;
            status("Installing and restarting…");
        }
        finally
        {
            if (!handedOff)
            {
                try { Directory.Delete(transaction, recursive: true); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
        }
    }

    [SupportedOSPlatform("windows")]
    private static string GetInstallDirectory()
    {
        using var key = Registry.CurrentUser.OpenSubKey(UninstallKey);
        var installed = key?.GetValue("InstallLocation") as string;
        var current = Path.TrimEndingDirectorySeparator(Path.GetFullPath(AppContext.BaseDirectory));
        if (string.IsNullOrWhiteSpace(installed) ||
            !string.Equals(Path.TrimEndingDirectorySeparator(Path.GetFullPath(installed)), current, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(Path.GetFullPath(Environment.ProcessPath ?? ""), Path.Combine(current, "ChatGPTUsage.Windows.exe"), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Run the Windows installer once before using Update now, or use View release.");
        return current;
    }

    internal static void VerifyChecksumFile(string text, UpdateAssetInfo asset)
    {
        var parts = text.Trim().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (text.Length > 4096 || parts.Length != 2 ||
            !string.Equals(parts[0], asset.Sha256, StringComparison.OrdinalIgnoreCase) ||
            (parts[1] != asset.Name && parts[1] != "*" + asset.Name))
            throw new InvalidDataException("The update checksums don’t match. Nothing was installed.");
    }

    internal static bool IsAllowedDownloadUri(Uri uri) => uri.Scheme == Uri.UriSchemeHttps && uri.IsDefaultPort
        && string.IsNullOrEmpty(uri.UserInfo) && new[] { "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com" }.Contains(uri.IdnHost);

    internal static async Task<string> DownloadAsync(UpdateAssetInfo asset, string directory)
    {
        using var handler = new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false };
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromMinutes(5) };
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(5));
        var uri = new Uri(asset.DownloadUrl);
        for (var redirect = 0; redirect <= 5; redirect++)
        {
            if (!IsAllowedDownloadUri(uri)) throw new InvalidDataException("The update download address is invalid.");
            using var response = await client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if ((int)response.StatusCode is >= 300 and < 400)
            {
                var location = response.Headers.Location ?? throw new InvalidDataException("The update download redirect is invalid.");
                uri = new Uri(uri, location);
                continue;
            }
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength is { } length && length != asset.Size)
                throw new InvalidDataException("The update download has an unexpected size.");
            var path = Path.Combine(directory, asset.Name);
            await using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, useAsync: true))
            await using (var input = await response.Content.ReadAsStreamAsync(timeout.Token))
            {
                var buffer = new byte[81920];
                long total = 0;
                int count;
                while ((count = await input.ReadAsync(buffer, timeout.Token)) > 0)
                {
                    total += count;
                    if (total > asset.Size) throw new InvalidDataException("The update download is larger than expected.");
                    await output.WriteAsync(buffer.AsMemory(0, count), timeout.Token);
                }
                if (total != asset.Size) throw new InvalidDataException("The update download was incomplete.");
            }
            await using var file = File.OpenRead(path);
            var digest = Convert.ToHexString(await SHA256.HashDataAsync(file, timeout.Token)).ToLowerInvariant();
            if (digest != asset.Sha256) throw new InvalidDataException("The downloaded update couldn’t be verified. Nothing was installed.");
            return path;
        }
        throw new InvalidDataException("The update download redirected too many times.");
    }
}
