<#
.SYNOPSIS
    Packages the Spriggan character pack release zip.

.DESCRIPTION
    The character's pak is built with Unreal Engine 5.3 and retoc, and its plugin with a record generator; neither is
    part of this repository (see README.md, "How it was made"). This script takes the built files and writes:
      dist\Sefiro.Spriggan-<version>\
        game\Paks\~mods\0000_ObmpSpriggan_P.pak/.ucas/.utoc
        game\Data\ObmpSpriggan.esp
        packs\spriggan.json
        Install-Client.ps1, Uninstall-Client.ps1, README.md, CHANGELOG.md
      dist\Sefiro.Spriggan-<version>.zip

.PARAMETER PakDir
    Folder with 0000_ObmpSpriggan_P.pak, .ucas and .utoc.

.PARAMETER Plugin
    Path of ObmpSpriggan.esp.

.PARAMETER Version
    Release version, for example 1.0.0.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $PakDir,
    [Parameter(Mandatory = $true)][string] $Plugin,
    [Parameter(Mandatory = $true)][string] $Version
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$name = "Sefiro.Spriggan-$Version"
$dist = Join-Path $root 'dist'
$out = Join-Path $dist $name
$zip = "$out.zip"
foreach ($ext in 'pak', 'ucas', 'utoc') {
    if (-not (Test-Path (Join-Path $PakDir "0000_ObmpSpriggan_P.$ext"))) { throw "Missing 0000_ObmpSpriggan_P.$ext in $PakDir" }
}
if ((Split-Path $Plugin -Leaf) -ne 'ObmpSpriggan.esp') { throw 'The plugin must be named ObmpSpriggan.esp.' }
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }

$paks = Join-Path $out 'game\Paks\~mods'
$data = Join-Path $out 'game\Data'
New-Item -ItemType Directory -Force $paks, $data, (Join-Path $out 'packs') | Out-Null
Copy-Item (Join-Path $PakDir '0000_ObmpSpriggan_P.*') $paks
Copy-Item $Plugin $data
Copy-Item (Join-Path $root 'packs\spriggan.json') (Join-Path $out 'packs')
Copy-Item (Join-Path $root 'install\Install-Client.ps1'), (Join-Path $root 'install\Uninstall-Client.ps1') $out
Copy-Item (Join-Path $root 'README.md'), (Join-Path $root 'CHANGELOG.md') $out

# Zip with "/" separators (Compress-Archive in Windows PowerShell 5.1 writes "\", which breaks unzip on Linux).
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    Get-ChildItem $out -Recurse -File | ForEach-Object {
        $entry = $_.FullName.Substring($dist.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entry, 'Optimal') | Out-Null
    }
} finally { $archive.Dispose() }
Write-Host "Release folder: $out"
Write-Host "Release zip:    $zip"
