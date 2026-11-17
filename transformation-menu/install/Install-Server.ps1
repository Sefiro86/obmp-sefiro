<#
.SYNOPSIS
    Installs Sefiro Transformation Menu on an OblivionMP server.

.DESCRIPTION
    Copies the Sefiro.TransformationMenu mod into the server's "mods" folder. The server hands its client half to
    every player who connects. An existing server\config.json (the list of allowed accounts) is kept.

    Stop the server before running this script: while it runs, the mod's files are locked.
    Each player also needs the UE4SS Lua mod: see Install-Client.ps1.

.PARAMETER ServerPath
    The OblivionMP server folder, the one that contains the "mods" folder.

.EXAMPLE
    .\Install-Server.ps1 -ServerPath "D:\OblivionMP\Server"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ServerPath
)

$ErrorActionPreference = 'Stop'
$ModId = 'Sefiro.TransformationMenu'
$here = $PSScriptRoot
$mods = Join-Path $ServerPath 'mods'
if (-not (Test-Path $mods)) { throw "No 'mods' folder in $ServerPath. Pass the OblivionMP server folder." }
if (-not (Test-Path (Join-Path $mods 'OblivionMP.Chat'))) {
    Write-Warning "OblivionMP.Chat is not in $mods. This mod depends on it and will not load without it."
}

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
Write-Host "Each player must also run Install-Client.ps1 (the UE4SS Lua mod) on their PC."
