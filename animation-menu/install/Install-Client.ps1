<#
.SYNOPSIS
    Installs the UE4SS Lua part of Sefiro Animation Menu on a player's PC.

.DESCRIPTION
    Copies lua\SefiroAnimationMenu into the ReadyM launcher's UE4SS mods folder
    (%APPDATA%\ReadyM.Launcher\Oblivion\Mods) and enables it in mods.txt. Your favorites (favorites.txt) are kept.

    Close the game before running this script. The C# half of the mod needs no install: the server sends it.

.EXAMPLE
    .\Install-Client.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Name = 'SefiroAnimationMenu'
$here = $PSScriptRoot
$mods = Join-Path $env:APPDATA 'ReadyM.Launcher\Oblivion\Mods'
if (Get-Process -Name 'OblivionRemastered*' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
if (-not (Test-Path $mods)) { throw "ReadyM launcher mods folder not found: $mods. Start OblivionMP once, then try again." }

$target = Join-Path $mods $Name
New-Item -ItemType Directory -Force (Join-Path $target 'Scripts') | Out-Null
Copy-Item (Join-Path $here "lua\$Name\Scripts\*") (Join-Path $target 'Scripts') -Force
Copy-Item (Join-Path $here "lua\$Name\catalog.txt"), (Join-Path $here "lua\$Name\enabled.txt") $target -Force

$list = Join-Path $mods 'mods.txt'
$lines = @()
if (Test-Path $list) { $lines = Get-Content $list }
if (-not ($lines | Where-Object { $_ -match "^\s*$Name\s*:" })) {
    Add-Content -Path $list -Value "$Name : 1"
} else {
    ($lines -replace "^\s*$Name\s*:.*$", "$Name : 1") | Set-Content -Path $list
}
Write-Host "Installed the Lua mod in $target and enabled it in mods.txt."
