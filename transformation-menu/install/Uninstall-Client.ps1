<#
.SYNOPSIS
    Removes the UE4SS Lua part of Sefiro Transformation Menu from a player's PC.

.DESCRIPTION
    Deletes %APPDATA%\ReadyM.Launcher\Oblivion\Mods\SefiroTransformation and SefiroTransformationSync, and their lines
    in mods.txt. Your character packs are deleted with it: copy the packs folder first if you want to keep them.
    Close the game before running this script. To remove the server half, delete
    mods\Sefiro.TransformationMenu from the server folder while the server is stopped.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$mods = Join-Path $env:APPDATA 'ReadyM.Launcher\Oblivion\Mods'
if (Get-Process -Name 'OblivionRemastered*' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
$list = Join-Path $mods 'mods.txt'
foreach ($Name in 'SefiroTransformation', 'SefiroTransformationSync') {
    $target = Join-Path $mods $Name
    if (Test-Path $target) { Remove-Item $target -Recurse -Force; Write-Host "Removed $target." }
    if (Test-Path $list) {
        (Get-Content $list | Where-Object { $_ -notmatch "^\s*$Name\s*:" }) | Set-Content -Path $list
    }
}
Write-Host 'Done.'
