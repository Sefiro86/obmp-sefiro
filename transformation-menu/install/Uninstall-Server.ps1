<#
.SYNOPSIS
    Removes Sefiro Transformation Menu from an OblivionMP server.

.DESCRIPTION
    Deletes mods\Sefiro.TransformationMenu (with its server\config.json: copy it first if you want to keep it) and the
    files Install-Server.ps1 put in modloader\@APPDATA\Mods\SefiroTransformation and SefiroTransformationSync. Character
    packs installed by other releases (packs\*.json) are left in place.

    Stop the server before running this script, and start it again afterwards. Players keep their local copy of the Lua
    mods until they run Uninstall-Client.ps1; without the server mod the Lua mods do nothing.

.PARAMETER ServerPath
    The OblivionMP server folder, the one that contains the "mods" and "modloader" folders.

.EXAMPLE
    .\Uninstall-Server.ps1 -ServerPath "D:\OblivionMP\Server"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ServerPath
)

$ErrorActionPreference = 'Stop'
$ModId = 'Sefiro.TransformationMenu'
$here = $PSScriptRoot
. (Join-Path $here 'ServerModloader.ps1')

$ServerPath = Assert-ServerFolder $ServerPath
$target = Join-Path $ServerPath "mods\$ModId"
if (Test-Path $target) { Remove-Item $target -Recurse -Force; Write-Host "Removed $target." }

$modloader = Get-ServerModloader $ServerPath
if ($modloader) {
    $count = Remove-PackageFromModloader $here $modloader
    Write-Host "Removed $count files from $modloader."
}
Write-Host 'Done. Start the server again.'
