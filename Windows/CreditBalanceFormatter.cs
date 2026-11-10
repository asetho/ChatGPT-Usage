using System.Globalization;

namespace ChatGPTUsage.Windows;

internal static class CreditBalanceFormatter
{
    public static string? Format(string raw, CultureInfo? culture = null)
    {
        if (!decimal.TryParse(raw, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture, out var balance)) return null;

        return Math.Round(balance, 0, MidpointRounding.AwayFromZero)
            .ToString("N0", culture ?? CultureInfo.CurrentCulture);
    }
}
