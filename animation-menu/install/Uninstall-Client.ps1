<#
.SYNOPSIS
    Removes the UE4SS Lua part of Sefiro Animation Menu from a player's PC.

.DESCRIPTION
    Deletes %APPDATA%\ReadyM.Launcher\Oblivion\Mods\SefiroAnimationMenu and its line in mods.txt.
    Your favorites (favorites.txt) are deleted with it: copy that file first if you want to keep it.
    Close the game before running this script. If a server you join still sends the Lua mod through its modloader,
    the ReadyM launcher puts it back: to remove the mod from a server, run Uninstall-Server.ps1 there.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Name = 'SefiroAnimationMenu'
$mods = Join-Path $env:APPDATA 'ReadyM.Launcher\Oblivion\Mods'
if (Get-Process -Name 'OblivionRemastered*' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
$target = Join-Path $mods $Name
if (Test-Path $target) { Remove-Item $target -Recurse -Force; Write-Host "Removed $target." }
$list = Join-Path $mods 'mods.txt'
if (Test-Path $list) {
    (Get-Content $list | Where-Object { $_ -notmatch "^\s*$Name\s*:" }) | Set-Content -Path $list
}
Write-Host 'Done.'
