<#
.SYNOPSIS
    Installs the UE4SS Lua part of Sefiro Transformation Menu on a player's PC.

.DESCRIPTION
    Only needed when the server does not send the Lua mods itself: Install-Server.ps1 puts them in the server's
    modloader, and the ReadyM launcher then copies them to every player. Use this script on servers that do not.

    Copies client-appdata\Mods\SefiroTransformation and SefiroTransformationSync into the ReadyM launcher's UE4SS mods
    folder (%APPDATA%\ReadyM.Launcher\Oblivion\Mods) and enables them in mods.txt. Your own character packs
    (packs\*.json) are kept.

    SefiroTransformationSync registers the forms of the installed character packs with the game ("syncMap" in a
    pack); it does nothing when no pack needs it.

    Close the game before running this script. The C# half of the mod needs no install: the server sends it.

.EXAMPLE
    .\Install-Client.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$mods = Join-Path $env:APPDATA 'ReadyM.Launcher\Oblivion\Mods'
if (Get-Process -Name 'OblivionRemastered*' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
if (-not (Test-Path $mods)) { throw "ReadyM launcher mods folder not found: $mods. Start OblivionMP once, then try again." }

$menu = Join-Path $mods 'SefiroTransformation'
New-Item -ItemType Directory -Force (Join-Path $menu 'Scripts'), (Join-Path $menu 'packs') | Out-Null
Copy-Item (Join-Path $here 'client-appdata\Mods\SefiroTransformation\Scripts\*') (Join-Path $menu 'Scripts') -Force
Copy-Item (Join-Path $here 'client-appdata\Mods\SefiroTransformation\packs\README.md') (Join-Path $menu 'packs') -Force
Copy-Item (Join-Path $here 'client-appdata\Mods\SefiroTransformation\enabled.txt') $menu -Force

$sync = Join-Path $mods 'SefiroTransformationSync'
New-Item -ItemType Directory -Force (Join-Path $sync 'Scripts') | Out-Null
Copy-Item (Join-Path $here 'client-appdata\Mods\SefiroTransformationSync\Scripts\*') (Join-Path $sync 'Scripts') -Force
Copy-Item (Join-Path $here 'client-appdata\Mods\SefiroTransformationSync\enabled.txt') $sync -Force

$list = Join-Path $mods 'mods.txt'
foreach ($Name in 'SefiroTransformation', 'SefiroTransformationSync') {
    $lines = @()
    if (Test-Path $list) { $lines = @(Get-Content $list) }
    if (-not ($lines | Where-Object { $_ -match "^\s*$Name\s*:" })) {
        Add-Content -Path $list -Value "$Name : 1"
    } else {
        ($lines -replace "^\s*$Name\s*:.*$", "$Name : 1") | Set-Content -Path $list
    }
}
Write-Host "Installed the Lua mods in $menu and $sync and enabled them in mods.txt."
