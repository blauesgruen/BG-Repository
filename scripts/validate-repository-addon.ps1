param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\repo.config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Assert-Equal([string]$Actual, [string]$Expected, [string]$Label) {
    if ($Actual -cne $Expected) {
        throw "$Label mismatch: expected '$Expected', got '$Actual'"
    }
}

function Assert-SameBytes([byte[]]$Actual, [byte[]]$Expected, [string]$Label) {
    if ([Convert]::ToBase64String($Actual) -cne [Convert]::ToBase64String($Expected)) {
        throw "$Label does not match its source file"
    }
}

function Read-ZipEntry([System.IO.Compression.ZipArchive]$Zip, [string]$Name) {
    $entry = $Zip.GetEntry($Name)
    if ($null -eq $entry) {
        throw "Repository ZIP is missing $Name"
    }
    $stream = $entry.Open()
    try {
        $memory = [System.IO.MemoryStream]::new()
        try {
            $stream.CopyTo($memory)
            return $memory.ToArray()
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$repoId = [string]$config.repository.id
$version = [string]$config.repository.version
$baseUrl = ([string]$config.repository.baseUrl).TrimEnd('/')
$repoDir = Join-Path $root $repoId
$addonPath = Join-Path $repoDir 'addon.xml'
$zipPath = Join-Path $repoDir "$repoId-$version.zip"

if (-not (Test-Path $addonPath)) { throw "Repository addon.xml is missing: $addonPath" }
if (-not (Test-Path $zipPath)) { throw "Repository installation ZIP is missing: $zipPath" }

[xml]$addonDoc = Get-Content -Raw -Path $addonPath
$addon = $addonDoc.DocumentElement
Assert-Equal $addon.GetAttribute('id') $repoId 'Repository add-on ID'
Assert-Equal $addon.GetAttribute('version') $version 'Repository version'
Assert-Equal $addon.GetAttribute('name') ([string]$config.repository.name) 'Repository name'
$dirs = @($addon.SelectNodes('extension[@point="xbmc.addon.repository"]/dir'))
$feeds = @($config.feeds)
if ($dirs.Count -ne $feeds.Count) {
    throw "Repository contains $($dirs.Count) feed entries, expected $($feeds.Count)"
}

for ($i = 0; $i -lt $feeds.Count; $i++) {
    $feed = $feeds[$i]
    $dir = $dirs[$i]
    $path = ([string]$feed.path).Trim('/')
    $feedDir = Join-Path $root $path
    $indexPath = Join-Path $feedDir 'addons.xml'
    $md5Path = Join-Path $feedDir 'addons.xml.md5'
    $gzipPath = Join-Path $feedDir 'addons.xml.gz'

    Assert-Equal $dir.GetAttribute('minversion') ([string]$feed.minversion) "$path minversion"
    Assert-Equal $dir.GetAttribute('maxversion') ([string]$feed.maxversion) "$path maxversion"
    Assert-Equal $dir.SelectSingleNode('info').InnerText "$baseUrl/$path/addons.xml" "$path info URL"
    Assert-Equal $dir.SelectSingleNode('info').GetAttribute('compressed') 'false' "$path compression setting"
    Assert-Equal $dir.SelectSingleNode('checksum').InnerText "$baseUrl/$path/addons.xml.md5" "$path checksum URL"
    Assert-Equal $dir.SelectSingleNode('datadir').InnerText "$baseUrl/$path/" "$path data URL"
    Assert-Equal $dir.SelectSingleNode('hashes').InnerText ([string]$config.hashes) "$path hash algorithm"

    if (-not (Test-Path $indexPath)) { throw "$path addons.xml is missing" }
    if (-not (Test-Path $md5Path)) { throw "$path addons.xml.md5 is missing" }
    if (-not (Test-Path $gzipPath)) { throw "$path addons.xml.gz is missing" }
    [xml]$index = Get-Content -Raw -Path $indexPath
    Assert-Equal $index.DocumentElement.LocalName 'addons' "$path index root"
    $expectedMd5 = (Get-FileHash -Algorithm MD5 $indexPath).Hash.ToLowerInvariant()
    $actualMd5 = (Get-Content -Raw -Path $md5Path).Trim().ToLowerInvariant()
    Assert-Equal $actualMd5 $expectedMd5 "$path index checksum"

    $inputStream = [System.IO.File]::OpenRead($gzipPath)
    try {
        $gzip = [System.IO.Compression.GZipStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
        try {
            $memory = [System.IO.MemoryStream]::new()
            try {
                $gzip.CopyTo($memory)
                Assert-SameBytes $memory.ToArray() ([System.IO.File]::ReadAllBytes($indexPath)) "$path compressed index"
            }
            finally {
                $memory.Dispose()
            }
        }
        finally {
            $gzip.Dispose()
        }
    }
    finally {
        $inputStream.Dispose()
    }

    foreach ($entry in @($index.SelectNodes('/addons/addon'))) {
        $relativeZip = $entry.SelectSingleNode('extension[@point="xbmc.addon.metadata"]/path')
        if ($null -eq $relativeZip -or [string]::IsNullOrWhiteSpace($relativeZip.InnerText)) {
            throw "$path index contains an add-on without a ZIP path"
        }
        $packagePath = Join-Path $feedDir ($relativeZip.InnerText.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path $packagePath)) { throw "$path references missing package $($relativeZip.InnerText)" }
    }
}

$omega = @($dirs | Where-Object { $_.SelectSingleNode('datadir').InnerText -eq "$baseUrl/omega/" })
$piers = @($dirs | Where-Object { $_.SelectSingleNode('datadir').InnerText -eq "$baseUrl/piers/" })
if ($omega.Count -ne 1 -or $piers.Count -ne 1) {
    throw 'Both the Omega and Piers repository entries are required'
}
foreach ($testCase in @(
    @{ version = '21.3.0'; feed = 'omega' },
    @{ version = '21.90.700'; feed = 'piers' },
    @{ version = '22.0.0'; feed = 'piers' }
)) {
    $matching = @($dirs | Where-Object {
        $current = [version]$testCase.version
        $current -ge [version]$_.GetAttribute('minversion') -and
        $current -le [version]$_.GetAttribute('maxversion')
    })
    if ($matching.Count -ne 1 -or $matching[0].SelectSingleNode('datadir').InnerText -ne "$baseUrl/$($testCase.feed)/") {
        throw "Wrong repository feed for Kodi $($testCase.version)"
    }
}

$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    Assert-SameBytes (Read-ZipEntry $zip "$repoId/addon.xml") ([System.IO.File]::ReadAllBytes($addonPath)) 'Repository ZIP addon.xml'
    $iconPath = Join-Path $repoDir 'icon.png'
    if (Test-Path $iconPath) {
        Assert-SameBytes (Read-ZipEntry $zip "$repoId/icon.png") ([System.IO.File]::ReadAllBytes($iconPath)) 'Repository ZIP icon'
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Repository add-on validation passed: $repoId $version; Omega and Piers feed indexes and ZIP are consistent."
