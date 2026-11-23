using System.Globalization;

namespace ChatGPTUsage.Windows;

internal static class CreditUseIndicator
{
    public static bool MayUseCredits(bool? ordinaryUsageAllowed,
        bool hasCredits, bool unlimited, string? rawBalance)
    {
        if (ordinaryUsageAllowed is not false || !hasCredits || unlimited) return false;

        return decimal.TryParse(rawBalance, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
            CultureInfo.InvariantCulture, out var balance) && balance > 0;
    }
}
