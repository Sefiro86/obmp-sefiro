<#
.SYNOPSIS
    Installs the Spriggan character pack on a player's PC.

.DESCRIPTION
    Only needed when the server does not send the Spriggan itself: Install-Server.ps1 puts it in the server's
    modloader, and the ReadyM launcher then copies it to every player. Use this script on servers that do not.

    Copies the character into the game and registers it with Sefiro Transformation Menu:
      0000_ObmpSpriggan_P.pak/.ucas/.utoc -> OblivionRemastered\Content\Paks\~mods
      ObmpSpriggan.esp                     -> OblivionRemastered\Content\Dev\ObvData\Data, added to Plugins.txt
      spriggan.json                        -> %APPDATA%\ReadyM.Launcher\Oblivion\Mods\SefiroTransformation\packs

    Needs the Lua mods of Sefiro Transformation Menu 0.9.1 or later on this PC (its Install-Client.ps1).
    Close the game before running this script.

.PARAMETER GamePath
    The Oblivion Remastered folder (the one that contains "OblivionRemastered"). If omitted, the Steam libraries are
    searched.

.EXAMPLE
    .\Install-Client.ps1
.EXAMPLE
    .\Install-Client.ps1 -GamePath "D:\Games\Oblivion Remastered"
#>
[CmdletBinding()]
param([string] $GamePath)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$plugin = 'ObmpSpriggan.esp'
if (Get-Process -Name 'OblivionRemastered*' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }

function Find-SteamGame {
    $roots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
        foreach ($v in $p.SteamPath, $p.InstallPath) { if ($v) { $roots += $v } }
    }
    $libraries = @()
    foreach ($r in $roots | Select-Object -Unique) {
        $libraries += $r
        $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libraries += $m.Groups[1].Value.Replace('\\', '\')
            }
        }
    }
    foreach ($lib in $libraries | Select-Object -Unique) {
        $candidate = Join-Path $lib 'steamapps\common\Oblivion Remastered'
        if (Test-Path (Join-Path $candidate 'OblivionRemastered\Content')) { return $candidate }
    }
    return $null
}

if (-not $GamePath) { $GamePath = Find-SteamGame }
if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath 'OblivionRemastered\Content'))) {
    throw 'Oblivion Remastered not found. Run again with -GamePath "<folder that contains OblivionRemastered>".'
}
$content = Join-Path $GamePath 'OblivionRemastered\Content'
$data = Join-Path $content 'Dev\ObvData\Data'
$paks = Join-Path $content 'Paks\~mods'
$menu = Join-Path $env:APPDATA 'ReadyM.Launcher\Oblivion\Mods\SefiroTransformation'
$sync = Join-Path $env:APPDATA 'ReadyM.Launcher\Oblivion\Mods\SefiroTransformationSync'
if (-not (Test-Path (Join-Path $menu 'Scripts\main.lua')) -or -not (Test-Path (Join-Path $sync 'Scripts\main.lua'))) {
    throw 'Sefiro Transformation Menu 0.9.1 or later is not installed on this PC. Run its Install-Client.ps1 first.'
}
if (-not (Test-Path $data)) { throw "Game data folder not found: $data" }

New-Item -ItemType Directory -Force $paks, (Join-Path $menu 'packs') | Out-Null
Copy-Item (Join-Path $here 'Paks\~mods\0000_ObmpSpriggan_P.*') $paks -Force
Copy-Item (Join-Path $here "Data\$plugin") $data -Force
Copy-Item (Join-Path $here 'client-appdata\Mods\SefiroTransformation\packs\spriggan.json') (Join-Path $menu 'packs') -Force

$list = Join-Path $data 'Plugins.txt'
$lines = @()
if (Test-Path $list) { $lines = @(Get-Content $list) }
if (-not ($lines | Where-Object { $_.Trim() -ieq $plugin })) {
    $raw = if (Test-Path $list) { [IO.File]::ReadAllText($list) } else { '' }
    $prefix = if ($raw -and -not $raw.EndsWith("`n")) { "`r`n" } else { '' }
    [IO.File]::AppendAllText($list, "$prefix$plugin`r`n")
    Write-Host "Added $plugin to $list."
}
Write-Host "Installed the Spriggan in $GamePath. Open the transformation menu with Alt+U: it is under Characters."
