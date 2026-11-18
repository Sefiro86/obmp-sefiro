<#
.SYNOPSIS
    Helper functions for Install-Server.ps1 and Uninstall-Server.ps1. Not meant to be run on its own.

.DESCRIPTION
    An OblivionMP (ReadyM) server has a "modloader" folder. Before the game starts, the ReadyM launcher copies to every
    player who joins the server everything in it:
      modloader\@GAME\...     -> <Oblivion Remastered>\OblivionRemastered\...
      modloader\@APPDATA\...  -> %APPDATA%\ReadyM.Launcher\Oblivion\...
    So paks, plugins (with Plugins.txt) and UE4SS Lua mods placed there reach every player, the host included.

    A release folder uses the same layout as the DogmaModInstaller packages:
      client-appdata\...  -> modloader\@APPDATA\...
      Paks\...            -> modloader\@GAME\Content\Paks\...
      Data\...            -> modloader\@GAME\Content\Dev\ObvData\Data\...   (plugins are also added to Plugins.txt)
#>

$script:PackageMap = [ordered]@{
    'client-appdata' = '@APPDATA'
    'Paks'           = '@GAME\Content\Paks'
    'Data'           = '@GAME\Content\Dev\ObvData\Data'
}

function Assert-ServerFolder([string] $ServerPath) {
    if (-not (Test-Path (Join-Path $ServerPath 'mods'))) {
        throw "No 'mods' folder in '$ServerPath'. Pass the OblivionMP server folder with -ServerPath."
    }
    $full = (Resolve-Path $ServerPath).Path
    $running = Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($full, [StringComparison]::OrdinalIgnoreCase) }
    if ($running) { throw "The server is running ($($running[0].ProcessName)). Stop it, then run this script again." }
    return $full
}

function Get-ServerModloader([string] $ServerPath) {
    $modloader = Join-Path $ServerPath 'modloader'
    if (-not (Test-Path $modloader)) { return $null }
    return $modloader
}

# Returns the "OblivionRemastered" folder of the game (the one that contains Content), or $null.
function Find-GameContentRoot([string] $GamePath) {
    $candidates = @()
    if ($GamePath) {
        $candidates += $GamePath, (Join-Path $GamePath 'OblivionRemastered')
    } else {
        $roots = @()
        foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
            $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
            foreach ($v in $p.SteamPath, $p.InstallPath) { if ($v) { $roots += $v } }
        }
        foreach ($r in $roots | Select-Object -Unique) {
            $libraries = @($r)
            $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
            if (Test-Path $vdf) {
                foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                    $libraries += $m.Groups[1].Value.Replace('\\', '\')
                }
            }
            foreach ($lib in $libraries | Select-Object -Unique) {
                $candidates += Join-Path $lib 'steamapps\common\Oblivion Remastered\OblivionRemastered'
            }
        }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'Content\Dev\ObvData\Data'))) { return $c }
    }
    return $null
}

# Every file of the release that goes into the modloader: @{ Source; Target (relative to modloader) }.
function Get-PackageFiles([string] $ReleasePath) {
    $files = @()
    foreach ($folder in $script:PackageMap.Keys) {
        $src = Join-Path $ReleasePath $folder
        if (-not (Test-Path $src)) { continue }
        $base = (Resolve-Path $src).Path.TrimEnd('\') + '\'
        foreach ($f in Get-ChildItem $src -Recurse -File) {
            if ($f.Name -ieq 'Plugins.txt') { continue }
            $files += [pscustomobject]@{
                Source = $f.FullName
                Target = Join-Path $script:PackageMap[$folder] $f.FullName.Substring($base.Length)
            }
        }
    }
    return $files
}

function Get-PackagePlugins([string] $ReleasePath) {
    $data = Join-Path $ReleasePath 'Data'
    if (-not (Test-Path $data)) { return @() }
    return @(Get-ChildItem $data -File | Where-Object { $_.Extension -in '.esp', '.esm' } | ForEach-Object { $_.Name })
}

# The ReadyM launcher cannot download an empty file from the modloader: the game fails to launch with
# "Couldn't download <file> of modloader". Refuse the whole install, before copying anything, if one is empty.
function Assert-NoEmptyFiles($Files) {
    $empty = @($Files | Where-Object { (Get-Item -LiteralPath $_.Source).Length -eq 0 })
    if ($empty.Count -gt 0) {
        throw ("These files are empty, and the ReadyM launcher cannot send empty files to players: " +
            ($empty.Target -join ', ') + '. Nothing was copied to the modloader.')
    }
}

function Copy-PackageToModloader([string] $ReleasePath, [string] $Modloader) {
    $files = @(Get-PackageFiles $ReleasePath)
    Assert-NoEmptyFiles $files
    foreach ($f in $files) {
        $target = Join-Path $Modloader $f.Target
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item $f.Source $target -Force
    }
    return $files.Count
}

function Remove-PackageFromModloader([string] $ReleasePath, [string] $Modloader) {
    $removed = 0
    $dirs = @{}
    foreach ($f in Get-PackageFiles $ReleasePath) {
        $target = Join-Path $Modloader $f.Target
        if (Test-Path $target) { Remove-Item $target -Force; $removed++ }
        $dirs[(Split-Path $target)] = $true
    }
    # Remove folders left empty, deepest first, but never the modloader's own top folders.
    $keep = @($Modloader, (Join-Path $Modloader '@APPDATA'), (Join-Path $Modloader '@APPDATA\Mods')) +
        @($script:PackageMap.Values | ForEach-Object { Join-Path $Modloader $_ })
    foreach ($d in $dirs.Keys | Sort-Object Length -Descending) {
        $cur = $d
        while ($cur -and $cur.Length -gt $Modloader.Length -and ($keep -notcontains $cur) -and (Test-Path $cur) -and
               -not (Get-ChildItem $cur -Force | Select-Object -First 1)) {
            Remove-Item $cur -Force
            $cur = Split-Path $cur
        }
    }
    return $removed
}

function Get-PluginName([string] $Line) {
    $t = $Line.Trim().TrimStart('#').Trim()
    if ($t -match '(?i)\.(esp|esm)$') { return $t }
    return ''
}

# Backups go to <server>\.sefiro-installer\backups, outside the modloader: anything inside it is sent to every player.
function Save-PluginsBackup([string] $Modloader, [string] $List) {
    if (-not (Test-Path $List)) { return }
    $dir = Join-Path (Split-Path $Modloader) '.sefiro-installer\backups'
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item $List (Join-Path $dir ("Plugins-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))) -Force
}

function Write-PluginsFile([string] $List, [string[]] $Lines) {
    $text = ($Lines -join "`r`n")
    if ($text) { $text += "`r`n" }
    [IO.File]::WriteAllText($List, $text, (New-Object Text.UTF8Encoding $false))
}

# Adds the plugins at the end of the modloader's Plugins.txt. That file replaces every player's Plugins.txt, so when it
# does not exist yet it starts as a copy of the host game's Plugins.txt (the full load order), never as an empty list.
function Add-ModloaderPlugins([string] $Modloader, [string[]] $Plugins, [string] $GamePath) {
    if (-not $Plugins -or $Plugins.Count -eq 0) { return }
    $dataDir = Join-Path $Modloader $script:PackageMap['Data']
    $list = Join-Path $dataDir 'Plugins.txt'
    $lines = New-Object System.Collections.ArrayList
    if (Test-Path $list) {
        foreach ($l in Get-Content $list) { [void]$lines.Add([string]$l) }
    } else {
        $game = Find-GameContentRoot $GamePath
        if (-not $game) {
            throw ("The server's modloader has no Plugins.txt yet, and Oblivion Remastered was not found to copy its " +
                'load order from. Run again with -GamePath "<folder that contains OblivionRemastered>".')
        }
        $gameList = Join-Path $game 'Content\Dev\ObvData\Data\Plugins.txt'
        if (-not (Test-Path $gameList)) { throw "Plugins.txt not found in the game: $gameList" }
        foreach ($l in Get-Content $gameList) { [void]$lines.Add([string]$l) }
        Write-Host "Created the modloader Plugins.txt from $gameList."
    }
    $changed = -not (Test-Path $list)
    foreach ($p in $Plugins) {
        $found = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ((Get-PluginName $lines[$i]) -ieq $p) {
                if ($lines[$i].Trim().StartsWith('#')) { $lines[$i] = $p; $changed = $true }
                $found = $true
                break
            }
        }
        if (-not $found) { [void]$lines.Add($p); $changed = $true; Write-Host "Added $p to the modloader Plugins.txt." }
    }
    if ($changed) {
        New-Item -ItemType Directory -Force $dataDir | Out-Null
        Save-PluginsBackup $Modloader $list
        Write-PluginsFile $list $lines.ToArray()
    }
}

function Remove-ModloaderPlugins([string] $Modloader, [string[]] $Plugins) {
    if (-not $Plugins -or $Plugins.Count -eq 0) { return }
    $list = Join-Path (Join-Path $Modloader $script:PackageMap['Data']) 'Plugins.txt'
    if (-not (Test-Path $list)) { return }
    $lines = @(Get-Content $list)
    $kept = @($lines | Where-Object { $Plugins -inotcontains (Get-PluginName $_) })
    if ($kept.Count -ne $lines.Count) {
        Save-PluginsBackup $Modloader $list
        Write-PluginsFile $list $kept
        Write-Host "Removed $($Plugins -join ', ') from the modloader Plugins.txt."
    }
}
