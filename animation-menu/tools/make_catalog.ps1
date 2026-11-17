<#
.SYNOPSIS
    Regenerates lua\SefiroAnimationMenu\catalog.txt from the game's pak.

.DESCRIPTION
    Lists every third-person animation in the game files, humanoid and creature (A_<Family>_* and AM_<Family>_*:
    Humanoid, Bear, Troll...), one per line as "name|/Game/path/name.name". The Lua lists them even when they are
    not in memory and loads them when you play them. Run it again after a game update.

    Needs retoc (https://github.com/trumank/retoc) to read the game's IoStore container.

.EXAMPLE
    .\make_catalog.ps1 -Retoc C:\tools\retoc.exe
#>
param(
    [string]$Utoc = 'C:\Program Files (x86)\Steam\steamapps\common\Oblivion Remastered\OblivionRemastered\Content\Paks\OblivionRemastered-Windows.utoc',
    [string]$Retoc = 'retoc.exe',
    [string]$Out = "$PSScriptRoot\..\lua\SefiroAnimationMenu\catalog.txt"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Utoc)) { throw "Game container not found: $Utoc. Pass -Utoc with the path of OblivionRemastered-Windows.utoc." }
$seen = @{}
$rows = New-Object System.Collections.Generic.List[string]
& $Retoc list --path $Utoc | ForEach-Object {
    if ($_ -match 'Content/((?:Art/Animation/(?:Humanoid|Creatures|Characters)|ArtOriginal/animations/Characters)/(?:\S*/)?(AM?_[A-Za-z0-9]+_[^/.]*))\.uasset') {
        $path, $name = $Matches[1], $Matches[2]
        if ($path -notmatch 'FirstPerson|/Facial/' -and $name -notmatch '_FP$' -and -not $seen.ContainsKey($name)) {
            $seen[$name] = $true
            $rows.Add("$name|/Game/$path.$name")
        }
    }
}
$rows.Sort([System.StringComparer]::Ordinal)
[System.IO.File]::WriteAllLines($Out, $rows, (New-Object System.Text.UTF8Encoding($false)))
"catalog: $($rows.Count) animations -> $Out"
