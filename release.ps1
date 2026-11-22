<#
  release.ps1 - builds dist\StrongLikeTauren-<version>.zip

  The zip holds a single top-level StrongLikeTauren\ folder with only runtime files:
  the .toc, every file the .toc lists, Media\SLT_Logo.tga, Media\SLT_Icon.tga,
  LICENSE, README.md and CHANGELOG.md.
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$name = 'StrongLikeTauren'
$tocPath = Join-Path $root "$name.toc"
if (-not (Test-Path -LiteralPath $tocPath)) { throw "Missing $name.toc in $root" }

$toc = Get-Content -LiteralPath $tocPath
$version = $null
foreach ($line in $toc) {
  if ($line -match '^\s*##\s*Version\s*:\s*(\S+)') { $version = $Matches[1]; break }
}
if (-not $version) { throw "No '## Version:' line found in $name.toc" }

# Files listed in the TOC (non-empty lines that aren't comments or metadata).
$files = New-Object System.Collections.Generic.List[string]
$files.Add("$name.toc")
foreach ($line in $toc) {
  $t = $line.Trim()
  if ($t -eq '' -or $t.StartsWith('#')) { continue }
  $files.Add($t)
}
foreach ($extra in 'Media\SLT_Logo.tga', 'Media\SLT_Icon.tga', 'LICENSE', 'README.md', 'CHANGELOG.md') { $files.Add($extra) }

$missing = @()
foreach ($f in $files) {
  if (-not (Test-Path -LiteralPath (Join-Path $root $f) -PathType Leaf)) { $missing += $f }
}
if ($missing.Count -gt 0) {
  throw ("Cannot build release: {0} file(s) missing:`n  {1}" -f $missing.Count, ($missing -join "`n  "))
}

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zipPath = Join-Path $dist "$name-$version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($f in ($files | Select-Object -Unique)) {
    $entry = "$name/" + ($f -replace '\\', '/')
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $root $f), $entry, [System.IO.Compression.CompressionLevel]::Optimal)
  }
} finally { $zip.Dispose() }

"Built $zipPath ({0} files)" -f ($files | Select-Object -Unique).Count
