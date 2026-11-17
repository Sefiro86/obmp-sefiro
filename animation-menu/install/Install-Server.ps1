<#
.SYNOPSIS
    Installs Sefiro Animation Menu on an OblivionMP server.

.DESCRIPTION
    Copies the Sefiro.AnimationMenu mod into the server's "mods" folder. The server hands its client half to every
    player who connects.

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
$ModId = 'Sefiro.AnimationMenu'
$here = $PSScriptRoot
$mods = Join-Path $ServerPath 'mods'
if (-not (Test-Path $mods)) { throw "No 'mods' folder in $ServerPath. Pass the OblivionMP server folder." }

$target = Join-Path $mods $ModId
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Copy-Item (Join-Path $here "mods\$ModId") $mods -Recurse
Write-Host "Installed $ModId in $target."
Write-Host "Each player must also run Install-Client.ps1 (the UE4SS Lua mod) on their PC."
