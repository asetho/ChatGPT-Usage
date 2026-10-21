using ChatGPTUsage.Windows;

var checks = 0;
void Check(bool condition, string description)
{
    if (!condition) throw new Exception(description);
    checks++;
}
void RejectChecksum(string text, UpdateAssetInfo asset)
{
    try { UpdateInstaller.VerifyChecksumFile(text, asset); }
    catch (InvalidDataException) { checks++; return; }
    throw new Exception("Accepted invalid checksum: " + text);
}

const string name = "ChatGPTUsage-Setup-1.0.25.exe";
var digest = new string('a', 64);
UpdateAssetInfo Asset(string file) => new(file,
    "https://github.com/asetho/ChatGPT-Usage/releases/download/v1.0.25/" + file, 90, "sha256:" + digest);
var installer = Asset(name);
var checksum = Asset(name + ".sha256");
var release = new UpdateCheckService.GitHubRelease("v1.0.25",
    "https://github.com/asetho/ChatGPT-Usage/releases/tag/v1.0.25", [installer, checksum]);
AvailableUpdateInfo? Parse(UpdateCheckService.GitHubRelease value) => UpdateCheckService.AvailableUpdate(value, new Version(1, 0, 24));

Check(Parse(release)?.Package?.Installer == installer, "Valid release did not offer installation");
Check(UpdateCheckService.AvailableUpdate(release, new Version(1, 0, 25)) is null, "Offered current version");
Check(UpdateCheckService.AvailableUpdate(release, new Version(1, 0, 26)) is null, "Offered older version");
Check(Parse(release with { Assets = null }) is { Package: null }, "Missing assets must retain manual release link");
Check(Parse(release with { Assets = [installer] }) is { Package: null }, "Accepted missing checksum");
Check(Parse(release with { Assets = [installer, installer, checksum] }) is { Package: null }, "Accepted duplicate installer");
foreach (var value in new[] {
    installer with { DownloadUrl = "https://example.com/" + name },
    installer with { DownloadUrl = installer.DownloadUrl.Replace("asetho", "other") },
    installer with { DownloadUrl = installer.DownloadUrl + "?download=1" },
    installer with { Digest = null }, installer with { Digest = "sha256:" + new string('g', 64) },
    installer with { Size = 0 }, installer with { Size = 600L * 1024 * 1024 }
}) Check(Parse(release with { Assets = [value, checksum] }) is { Package: null }, "Accepted invalid installer metadata");
foreach (var value in new[] {
    release with { HtmlUrl = release.HtmlUrl.Replace("asetho", "other") },
    release with { HtmlUrl = release.HtmlUrl.Replace("github.com", "github.com:444") },
    release with { Draft = true }, release with { Prerelease = true }, release with { TagName = "v+1.0.25" }
}) Check(Parse(value) is null, "Accepted invalid release");
UpdateInstaller.VerifyChecksumFile($"{digest}  {name}\n", installer);
UpdateInstaller.VerifyChecksumFile($"{digest.ToUpperInvariant()} *{name}\n", installer);
checks += 2;
RejectChecksum($"{digest}  wrong.exe", installer);
RejectChecksum($"{new string('b', 64)}  {name}", installer);
RejectChecksum($"{digest}  {name}\nextra", installer);
RejectChecksum("invalid", installer);
foreach (var url in new[] { "https://github.com/file", "https://release-assets.githubusercontent.com/file?signature=example", "https://objects.githubusercontent.com/file" })
    Check(UpdateInstaller.IsAllowedDownloadUri(new Uri(url)), "Rejected GitHub download host");
foreach (var url in new[] { "http://github.com/file", "https://github.com:444/file", "https://user@github.com/file", "https://github.com.example.com/file", "file:///tmp/package.exe" })
    Check(!UpdateInstaller.IsAllowedDownloadUri(new Uri(url)), "Accepted unsafe redirect");
Console.WriteLine($"PASS: {checks} update checks");

// Optional network integration check against the repository's actual public assets.
if (args.Contains("--download-latest"))
{
    var update = await UpdateCheckService.FetchAvailableUpdateAsync(new Version(0, 0, 0));
    var package = update?.Package ?? throw new Exception("Latest release has no verified update package");
    var temporary = Path.Combine(Path.GetTempPath(), "ChatGPTUsage-update-test-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(temporary);
    try
    {
        await UpdateInstaller.DownloadAsync(package.Installer, temporary);
        var file = await UpdateInstaller.DownloadAsync(package.Checksum, temporary);
        UpdateInstaller.VerifyChecksumFile(await File.ReadAllTextAsync(file), package.Installer);
        Console.WriteLine($"PASS: public Windows v{update!.Version} download, redirects, size and SHA256");
    }
    finally { Directory.Delete(temporary, recursive: true); }
}
