using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ChatGPTUsage.Windows;

public sealed record AvailableUpdateInfo(string Version, string ReleaseUrl, UpdatePackageInfo? Package = null);
public sealed record UpdatePackageInfo(UpdateAssetInfo Installer, UpdateAssetInfo Checksum);
public sealed record UpdateAssetInfo(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("browser_download_url")] string DownloadUrl,
    [property: JsonPropertyName("size")] long Size,
    [property: JsonPropertyName("digest")] string? Digest)
{
    public string? Sha256 => Digest is { } value && value.StartsWith("sha256:", StringComparison.Ordinal)
        && value.Length == 71 && value.AsSpan(7).IndexOfAnyExcept("0123456789abcdefABCDEF") < 0
            ? value[7..].ToLowerInvariant() : null;
}

internal static class UpdateCheckService
{
    private static readonly Uri LatestReleaseUri = new(
        "https://api.github.com/repos/asetho/ChatGPT-Usage/releases/latest");

    private static readonly HttpClient Client = new()
    {
        Timeout = TimeSpan.FromSeconds(8)
    };

    public static Version CurrentVersion =>
        Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(0, 0, 0);

    public static string CurrentVersionText => FormatVersion(CurrentVersion);

    public static async Task<AvailableUpdateInfo?> FetchAvailableUpdateAsync(
        Version currentVersion,
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseUri);
        request.Headers.Accept.ParseAdd("application/vnd.github+json");
        request.Headers.TryAddWithoutValidation("X-GitHub-Api-Version", "2026-03-10");
        request.Headers.UserAgent.ParseAdd($"asetho-ChatGPT-Usage/{FormatVersion(currentVersion)}");

        using var response = await Client.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var body = await response.Content.ReadAsStreamAsync(cancellationToken);
        var release = await JsonSerializer.DeserializeAsync<GitHubRelease>(
            body,
            cancellationToken: cancellationToken);

        return AvailableUpdate(release, currentVersion);
    }

    internal static AvailableUpdateInfo? AvailableUpdate(
        GitHubRelease? release,
        Version currentVersion)
    {
        if (release is null ||
            !TryParseReleaseVersion(release.TagName, out var latestVersion) ||
            latestVersion <= currentVersion ||
            release.Draft || release.Prerelease ||
            !IsReleaseUrl(release.HtmlUrl, $"/asetho/ChatGPT-Usage/releases/tag/{release.TagName}", out var releaseUri))
        {
            return null;
        }

        var version = FormatVersion(latestVersion);
        var name = $"ChatGPTUsage-Setup-{version}.exe";
        UpdateAssetInfo? Asset(string file, long maximumSize)
        {
            var matches = (release.Assets ?? []).Where(asset => asset.Name == file).ToArray();
            return matches.Length == 1 && matches[0].Size > 0 && matches[0].Size <= maximumSize && matches[0].Sha256 is not null
                && IsReleaseUrl(matches[0].DownloadUrl, $"/asetho/ChatGPT-Usage/releases/download/{release.TagName}/{file}", out _)
                    ? matches[0] : null;
        }
        var installer = Asset(name, 512L * 1024 * 1024);
        var checksum = Asset(name + ".sha256", 4096);
        var package = installer is not null && checksum is not null ? new UpdatePackageInfo(installer, checksum) : null;
        return new AvailableUpdateInfo(version, releaseUri!.AbsoluteUri, package);
    }

    internal static bool IsReleaseUrl(string candidate, string path, out Uri? uri)
    {
        return Uri.TryCreate(candidate, UriKind.Absolute, out uri) && uri.Scheme == Uri.UriSchemeHttps
            && uri.IsDefaultPort && string.IsNullOrEmpty(uri.UserInfo) && uri.IdnHost == "github.com"
            && uri.AbsolutePath == path && string.IsNullOrEmpty(uri.Query) && string.IsNullOrEmpty(uri.Fragment);
    }

    private static bool TryParseReleaseVersion(string tagName, out Version version)
    {
        var normalized = tagName.Trim();
        if (normalized.StartsWith('v') || normalized.StartsWith('V'))
        {
            normalized = normalized[1..];
        }

        if (!Version.TryParse(normalized, out var parsed) ||
            normalized.Any(character => character != '.' && !char.IsAsciiDigit(character)) ||
            parsed.Major < 0 || parsed.Minor < 0 || parsed.Build < 0 || parsed.Revision >= 0)
        {
            version = new Version();
            return false;
        }

        version = parsed;
        return true;
    }

    private static string FormatVersion(Version version) =>
        $"{version.Major}.{version.Minor}.{Math.Max(version.Build, 0)}";

    internal sealed record GitHubRelease(
        [property: JsonPropertyName("tag_name")] string TagName,
        [property: JsonPropertyName("html_url")] string HtmlUrl,
        [property: JsonPropertyName("assets")] UpdateAssetInfo[]? Assets = null,
        [property: JsonPropertyName("draft")] bool Draft = false,
        [property: JsonPropertyName("prerelease")] bool Prerelease = false);
}
