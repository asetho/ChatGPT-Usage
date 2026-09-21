using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;

namespace ChatGPTUsage.Windows;

internal static class ExternalLinkLauncher
{
    private static readonly HashSet<string> AllowedHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "chatgpt.com",
        "github.com",
        "help-lb.openai.com"
    };

    public static bool TryOpen(string candidate)
    {
        if (!TryCreateAllowedUri(candidate, out var uri))
        {
            return false;
        }

        Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
        return true;
    }

    internal static bool TryCreateAllowedUri(string candidate, [NotNullWhen(true)] out Uri? uri)
    {
        uri = null;
        if (!Uri.TryCreate(candidate, UriKind.Absolute, out var parsed) ||
            parsed.Scheme != Uri.UriSchemeHttps ||
            !parsed.IsDefaultPort ||
            !string.IsNullOrEmpty(parsed.UserInfo) ||
            parsed.HostNameType != UriHostNameType.Dns ||
            !AllowedHosts.Contains(parsed.IdnHost))
        {
            return false;
        }

        uri = parsed;
        return true;
    }
}
