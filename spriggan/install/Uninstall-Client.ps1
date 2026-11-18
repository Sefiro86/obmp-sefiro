<#
.SYNOPSIS
    Removes the Spriggan character pack from a player's PC.

.DESCRIPTION
    Deletes the Spriggan pak files from Content\Paks\~mods, ObmpSpriggan.esp from the game data folder and from
    Plugins.txt, and spriggan.json from the Transformation Menu packs folder. Turn back to normal before uninstalling,
    and close the game. If a server you join still sends the Spriggan through its modloader, the ReadyM launcher puts
    it back: to remove it from a server, run Uninstall-Server.ps1 there.

.PARAMETER GamePath
    The Oblivion Remastered folder (the one that contains "OblivionRemastered"). If omitted, the Steam libraries are
    searched.
#>
[CmdletBinding()]
param([string] $GamePath)

$ErrorActionPreference = 'Stop'
$plugin = 'ObmpSpriggan.esp'
if (Get-Process -Name 'OblivionRemastered*' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }

if (-not $GamePath) {
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
        foreach ($r in $p.SteamPath, $p.InstallPath) {
            if (-not $r) { continue }
            $libs = @($r)
            $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
            if (Test-Path $vdf) {
                foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value.Replace('\\', '\') }
            }
            foreach ($lib in $libs) {
                $c = Join-Path $lib 'steamapps\common\Oblivion Remastered'
                if (-not $GamePath -and (Test-Path (Join-Path $c 'OblivionRemastered\Content'))) { $GamePath = $c }
            }
        }
    }
}
if (-not $GamePath) { throw 'Oblivion Remastered not found. Run again with -GamePath "<folder that contains OblivionRemastered>".' }
$content = Join-Path $GamePath 'OblivionRemastered\Content'
$data = Join-Path $content 'Dev\ObvData\Data'

Get-ChildItem (Join-Path $content 'Paks\~mods') -Filter '0000_ObmpSpriggan_P.*' -ErrorAction SilentlyContinue | Remove-Item -Force
Remove-Item (Join-Path $data $plugin) -Force -ErrorAction SilentlyContinue
$list = Join-Path $data 'Plugins.txt'
if (Test-Path $list) { (Get-Content $list | Where-Object { $_.Trim() -ine $plugin }) | Set-Content -Path $list }
Remove-Item (Join-Path $env:APPDATA 'ReadyM.Launcher\Oblivion\Mods\SefiroTransformation\packs\spriggan.json') -Force -ErrorAction SilentlyContinue
Write-Host 'Removed the Spriggan.'
