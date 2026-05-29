param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [string]$ReleaseTag,

    [string]$FeedPath = 'omega'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$validPlatforms = @(
    'all',
    'linux',
    'linux-aarch64',
    'linux-armv7',
    'linux-x86_64',
    'osx',
    'osx64',
    'osx-x86_64',
    'osx32',
    'osx-i686',
    'ios',
    'ios-armv7',
    'ios-aarch64',
    'windx',
    'windows',
    'windows-i686',
    'windows-x86_64',
    'windowsstore',
    'android',
    'android-armv7',
    'android-aarch64',
    'android-i686',
    'tvos',
    'tvos-aarch64'
)

$blockedPlatforms = @(
    'linux'
)

function Get-AddonXmlFromZip([string]$ZipPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $zip.Entries |
            Where-Object { $_.FullName -match '^[^/\\]+/addon\.xml$' } |
            Select-Object -First 1

        if ($null -eq $entry) {
            throw "No addon.xml found at the add-on root"
        }

        $stream = $entry.Open()
        try {
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
            try {
                return $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Copy-AddonAssetsFromZip([string]$ZipPath, [string]$TargetDirectory) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entries = $zip.Entries |
            Where-Object { $_.FullName -match '^[^/\\]+/(icon\.png|resources/icon\.png)$' }

        foreach ($entry in $entries) {
            $relativePath = ($entry.FullName -replace '^[^/\\]+[/\\]', '').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $targetPath = Join-Path $TargetDirectory $relativePath
            $targetParent = Split-Path -Parent $targetPath
            New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
        }
    }
    finally {
        $zip.Dispose()
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI 'gh' is required for private release imports."
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$tempDir = Join-Path $env:TEMP ('kodi-release-import-' + [guid]::NewGuid().ToString('N'))
$ownerRepoName = ($Repository -replace '[^a-zA-Z0-9._-]+', '_')
$incomingDir = Join-Path $projectRoot "incoming\$ownerRepoName\$ReleaseTag"
$feedDir = Join-Path $projectRoot $FeedPath
$report = @()

New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
New-Item -ItemType Directory -Force -Path $incomingDir | Out-Null
New-Item -ItemType Directory -Force -Path $feedDir | Out-Null

try {
    gh release download $ReleaseTag -R $Repository --dir $tempDir --pattern '*.zip'

    $zipFiles = Get-ChildItem -Path $tempDir -Filter '*.zip' -File | Sort-Object Name
    foreach ($zipFile in $zipFiles) {
        Copy-Item -Force -Path $zipFile.FullName -Destination $incomingDir

        try {
            $addonDoc = [System.Xml.XmlDocument]::new()
            $addonDoc.LoadXml((Get-AddonXmlFromZip $zipFile.FullName))
            $addon = $addonDoc.DocumentElement
            $metadata = @($addon.SelectNodes('extension[@point="xbmc.addon.metadata"]')) | Select-Object -First 1
            $platformNode = if ($metadata) { $metadata.SelectSingleNode('platform') } else { $null }
            $platform = if ($platformNode) { $platformNode.InnerText.Trim() } else { '' }
            $id = $addon.GetAttribute('id')
            $version = $addon.GetAttribute('version')
            $reason = ''
            $imported = $false

            if ($addon.LocalName -ne 'addon') {
                $reason = 'root element is not addon'
            }
            elseif ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($version)) {
                $reason = 'missing id or version'
            }
            elseif ([string]::IsNullOrWhiteSpace($platform)) {
                $reason = 'missing platform'
            }
            elseif ($blockedPlatforms -contains $platform) {
                $reason = "ambiguous platform '$platform'"
            }
            elseif ($validPlatforms -notcontains $platform) {
                $reason = "unsupported platform '$platform'"
            }
            else {
                $targetDir = Join-Path $feedDir "$id+$platform"
                $targetZip = Join-Path $targetDir "$id-$version.zip"
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
                Copy-Item -Force -Path $zipFile.FullName -Destination $targetZip
                Copy-AddonAssetsFromZip $zipFile.FullName $targetDir
                $reason = 'imported'
                $imported = $true
            }

            $report += [pscustomobject]@{
                asset = $zipFile.Name
                id = $id
                version = $version
                platform = $platform
                imported = $imported
                result = $reason
            }
        }
        catch {
            $report += [pscustomobject]@{
                asset = $zipFile.Name
                id = ''
                version = ''
                platform = ''
                imported = $false
                result = $_.Exception.Message
            }
        }
    }
}
finally {
    Remove-Item -Recurse -Force $tempDir
}

$reportPath = Join-Path $incomingDir 'asset-report.json'
$report | ConvertTo-Json | Set-Content -Encoding UTF8 -Path $reportPath
$report | Format-Table -AutoSize
Write-Host "Report written to $reportPath"
