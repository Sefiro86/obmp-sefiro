using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace Sefiro.TransformationMenu.Client;

/// <summary>
/// Runs Oblivion script commands on the local player's game, on the TES thread, through the small native core
/// shipped with this mod (<c>SefiroTransformation_native.native</c>, built from the same source as ConsoleBridge's
/// <c>obmp_native</c>). It hooks the end of Oblivion's frame; if another mod already hooked the same spot it chains
/// after it, so it coexists with ConsoleBridge. Only used for <c>unequipitem</c>/<c>equipitem</c> on the local player
/// (unarmed while transformed into a creature). Shipped as <c>.native</c>: ReadyM's mod loader opens every
/// <c>*.dll</c> in the folder with Mono.Cecil and a native DLL would crash the startup.
/// </summary>
public static unsafe class GameCommands
{
    public const string FileName = "SefiroTransformation_native.native";
    private const int ExpectedApiVersion = 2;

    private static ILogger? _logger;
    private static delegate* unmanaged<int> _apiVersion;
    private static delegate* unmanaged<delegate* unmanaged<int, byte*, void>, void> _setLogger;
    private static delegate* unmanaged<int> _init;
    private static delegate* unmanaged<byte*, int, int> _runCommand;
    private static delegate* unmanaged<int, int> _commandState;

    public static bool Active { get; private set; }

    /// <summary>Loads the native core and installs the frame hook. Never throws.</summary>
    public static bool Start(string modDirectory, ILogger logger)
    {
        _logger = logger;
        var path = Path.Combine(modDirectory, FileName);
        try
        {
            var lib = NativeLibrary.Load(path);
            _apiVersion = (delegate* unmanaged<int>)NativeLibrary.GetExport(lib, "obmp_api_version");
            _setLogger = (delegate* unmanaged<delegate* unmanaged<int, byte*, void>, void>)NativeLibrary.GetExport(lib, "obmp_set_logger");
            _init = (delegate* unmanaged<int>)NativeLibrary.GetExport(lib, "obmp_init");
            _runCommand = (delegate* unmanaged<byte*, int, int>)NativeLibrary.GetExport(lib, "obmp_run_command");
            _commandState = (delegate* unmanaged<int, int>)NativeLibrary.GetExport(lib, "obmp_command_state");
        }
        catch (Exception e)
        {
            logger.LogError(e, "[Transform] could not load the native core from {Path}: creatures keep the weapons in hand", path);
            return false;
        }
        var version = _apiVersion();
        if (version != ExpectedApiVersion)
        {
            logger.LogError("[Transform] native core API v{Got}, expected v{Expected}: disabled", version, ExpectedApiVersion);
            return false;
        }
        _setLogger(&OnNativeLog);
        Active = _init() == 0;
        if (Active) logger.LogInformation("[Transform] native core active (api v{Version})", version);
        else logger.LogWarning("[Transform] native core NOT active: creatures keep the weapons in hand");
        return Active;
    }

    /// <summary>
    /// Queues a script command (printable ASCII, Oblivion console syntax) for the TES thread. Returns a ticket &gt; 0,
    /// or a negative error (-1 not active, -2 invalid text, -3 ExecuteCommand not found, -4 too long, -5 memory).
    /// </summary>
    public static int Run(string command)
    {
        if (!Active) return -1;
        var bytes = System.Text.Encoding.ASCII.GetBytes(command);
        fixed (byte* p = bytes)
            return _runCommand(p, bytes.Length);
    }

    /// <summary>0 waiting, 1 executed, 2 game exception, 3 skipped, -1 unknown/expired.</summary>
    public static int State(int ticket) => Active ? _commandState(ticket) : -1;

    [UnmanagedCallersOnly]
    private static void OnNativeLog(int level, byte* utf8)
    {
        var text = Marshal.PtrToStringUTF8((nint)utf8) ?? string.Empty;
        var logLevel = level switch { >= 3 => LogLevel.Error, 2 => LogLevel.Warning, _ => LogLevel.Information };
        _logger?.Log(logLevel, "[Transform] {NativeMessage}", text);
    }
}
