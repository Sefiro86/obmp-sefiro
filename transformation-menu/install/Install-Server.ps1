<#
.SYNOPSIS
    Installs Sefiro Transformation Menu on an OblivionMP server, for every player.

.DESCRIPTION
    1. Copies the Sefiro.TransformationMenu mod into the server's "mods" folder. The server hands its client half to
       every player who connects. An existing server\config.json (the list of allowed accounts) is kept.
    2. Copies the UE4SS Lua mods SefiroTransformation and SefiroTransformationSync into the server's
       modloader\@APPDATA\Mods. The ReadyM launcher copies them to every player's PC before the game starts, so players
       install nothing by hand. Character packs already in the modloader (packs\*.json) are kept.

    Stop the server before running this script, and start it again afterwards: the server reads the modloader when it
    starts. Run it again after updating this mod.

.PARAMETER ServerPath
    The OblivionMP server folder, the one that contains the "mods" and "modloader" folders.

.PARAMETER SkipModloader
    Only install the server mod. Each player then runs Install-Client.ps1 on their PC (the old way).

.EXAMPLE
    .\Install-Server.ps1 -ServerPath "D:\OblivionMP\Server"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ServerPath,
    [switch] $SkipModloader
)

$ErrorActionPreference = 'Stop'
$ModId = 'Sefiro.TransformationMenu'
$here = $PSScriptRoot
. (Join-Path $here 'ServerModloader.ps1')

$ServerPath = Assert-ServerFolder $ServerPath
$mods = Join-Path $ServerPath 'mods'
if (-not (Test-Path (Join-Path $mods 'OblivionMP.Chat'))) {
    Write-Warning "OblivionMP.Chat is not in $mods. This mod depends on it and will not load without it."
}

# 1. Server mod
$target = Join-Path $mods $ModId
$config = Join-Path $target 'server\config.json'
$keep = $null
if (Test-Path $config) { $keep = Get-Content $config -Raw }
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Copy-Item (Join-Path $here "mods\$ModId") $mods -Recurse
if ($keep) {
    Set-Content -Path $config -Value $keep -NoNewline -Encoding utf8
    Write-Host "Kept your existing server\config.json."
}
Write-Host "Installed $ModId in $target."

# 2. Lua mods, for every player
if ($SkipModloader) {
    Write-Host 'Skipped the modloader: each player must run Install-Client.ps1 on their PC.'
    return
}
$modloader = Get-ServerModloader $ServerPath
if (-not $modloader) {
    Write-Warning "No 'modloader' folder in $ServerPath, so the Lua mods cannot be sent to players. Each player must run Install-Client.ps1 on their PC."
    return
}
$count = Copy-PackageToModloader $here $modloader
Write-Host "Copied $count files to $modloader\@APPDATA\Mods (SefiroTransformation, SefiroTransformationSync)."
Write-Host 'Start the server again: every player receives the Lua mods from the ReadyM launcher when they join.'
