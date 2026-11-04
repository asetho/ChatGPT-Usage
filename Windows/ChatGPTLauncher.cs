using System.Runtime.InteropServices;

namespace ChatGPTUsage.Windows;

internal static class ChatGPTLauncher
{
    private const string AppUserModelId = "OpenAI.Codex_2p2nqsd0c76g0!App";

    public static void Open()
    {
        try
        {
            var manager = (IApplicationActivationManager)(object)new ApplicationActivationManager();
            try
            {
                // Activate the installed Store app, including an already running instance.
                if (manager.ActivateApplication(AppUserModelId, null, 0x2, out _) == 0) return;
            }
            finally
            {
                Marshal.ReleaseComObject(manager);
            }
        }
        catch (COMException) { }
        catch (InvalidCastException) { }

        ExternalLinkLauncher.TryOpen("https://chatgpt.com/");
    }

    [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    private sealed class ApplicationActivationManager { }

    [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IApplicationActivationManager
    {
        [PreserveSig]
        int ActivateApplication(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string? arguments,
            uint options,
            out uint processId);
    }
}
