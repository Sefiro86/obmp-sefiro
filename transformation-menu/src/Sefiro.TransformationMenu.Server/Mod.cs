using Microsoft.Extensions.Logging;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Server;

[ModEntry]
public sealed partial class Mod(ILogger logger)
{
    private void Init() => logger.LogInformation("[Transform] loaded: chat command /transform");
}

/// <summary>Settings read from config.json in the mod's server/ folder.</summary>
[ModConfig]
public sealed partial class TransformConfig
{
    /// <summary>ReadyM accounts (GUID) allowed to use /transform. Empty = everyone.</summary>
    public List<string> AllowedAccounts { get; set; } = [];
}
