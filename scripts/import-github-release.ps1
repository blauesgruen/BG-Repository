param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [string]$ReleaseTag,

    [string]$FeedPath = 'omega',

    [string]$ConfigPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot '..\repo.config.json'
}

function Get-AddonXmlFromZip([string]$ZipPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $zip.Entries |
            Where-Object { $_.FullName -match '^[^/\\]+/addon\.xml$' } |
            Select-Object -First 1

        if ($null -eq $entry) {
            throw "No addon.xml found at the add-on root in $ZipPath"
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

function Get-ReleaseVersion([string]$Tag) {
    if ($Tag -match '(\d+\.\d+\.\d+)') {
        return $Matches[1]
    }

    return ''
}

function Get-PackageRuleFromAssetName([string]$AssetName) {
    if ($AssetName -match '(Amlogic-ng|coreelec-ng)') {
        return [pscustomobject]@{ target = 'coreelec-ng'; expectedId = 'pvr.satip.coreelec-ng'; expectedPlatform = 'linux' }
    }
    if ($AssetName -match '(Amlogic-ne|coreelec-ne)') {
        return [pscustomobject]@{ target = 'coreelec-ne'; expectedId = 'pvr.satip.coreelec-ne'; expectedPlatform = 'linux' }
    }
    if ($AssetName -match 'linux-x86_64') {
        return [pscustomobject]@{ target = 'linux-x86_64'; expectedId = 'pvr.satip.linux-x86_64'; expectedPlatform = 'linux' }
    }
    if ($AssetName -match 'libreelec-rpi4-aarch64') {
        return [pscustomobject]@{ target = 'libreelec-rpi4-aarch64'; expectedId = 'pvr.satip.libreelec-rpi4-aarch64'; expectedPlatform = 'linux' }
    }
    if ($AssetName -match 'windows-(x64|x86_64)') {
        return [pscustomobject]@{ target = 'windows-x86_64'; expectedId = 'pvr.satip'; expectedPlatform = 'windows-x86_64' }
    }
    if ($AssetName -match 'android-aarch64') {
        return [pscustomobject]@{ target = 'android-aarch64'; expectedId = 'pvr.satip'; expectedPlatform = 'android-aarch64' }
    }
    if ($AssetName -match 'android-armv7') {
        return [pscustomobject]@{ target = 'android-armv7'; expectedId = 'pvr.satip'; expectedPlatform = 'android-armv7' }
    }

    return $null
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI 'gh' is required for private release imports."
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$releaseVersion = Get-ReleaseVersion $ReleaseTag
$feedDir = Join-Path $projectRoot $FeedPath

$tempDir = Join-Path $env:TEMP ('kodi-release-import-' + [guid]::NewGuid().ToString('N'))
$ownerRepoName = ($Repository -replace '[^a-zA-Z0-9._-]+', '_')
$incomingDir = Join-Path $projectRoot "incoming\$ownerRepoName\$ReleaseTag"
$report = @()
$cleanedFeed = $false

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
            $rule = Get-PackageRuleFromAssetName $zipFile.Name
            $target = if ($null -ne $rule) { [string]$rule.target } else { '' }
            $expectedId = if ($null -ne $rule) { [string]$rule.expectedId } else { '' }
            $expectedPlatform = if ($null -ne $rule) { [string]$rule.expectedPlatform } else { '' }
            $reason = ''
            $imported = $false

            if ($addon.LocalName -ne 'addon') {
                $reason = 'root element is not addon'
            }
            elseif ([string]::IsNullOrWhiteSpace($target)) {
                $reason = 'no target rule matched asset name'
            }
            elseif ($id -ne $expectedId) {
                $reason = "unexpected addon id '$id' for target '$target', expected '$expectedId'"
            }
            elseif ([string]::IsNullOrWhiteSpace($version)) {
                $reason = 'missing version'
            }
            elseif (-not [string]::IsNullOrWhiteSpace($releaseVersion) -and $version -ne $releaseVersion) {
                $reason = "version '$version' does not match release tag '$ReleaseTag'"
            }
            elseif ([string]::IsNullOrWhiteSpace($platform)) {
                $reason = 'missing platform'
            }
            elseif (-not [string]::IsNullOrWhiteSpace($expectedPlatform) -and $platform -ne $expectedPlatform) {
                $reason = "platform '$platform' does not match target '$target' expected platform '$expectedPlatform'"
            }
            else {
                if (-not $cleanedFeed) {
                    foreach ($oldTarget in @('android-aarch64', 'android-armv7', 'coreelec-ne', 'coreelec-ng', 'libreelec-rpi4-aarch64', 'linux-x86_64', 'windows-x86_64')) {
                        $oldTargetDir = Join-Path $feedDir $oldTarget
                        if (Test-Path $oldTargetDir) {
                            Remove-Item -Recurse -Force $oldTargetDir
                        }
                    }
                    Get-ChildItem -Path $feedDir -Directory -Filter 'pvr.satip+*' |
                        Remove-Item -Recurse -Force
                    $cleanedFeed = $true
                }

                $targetDir = Join-Path $feedDir $target
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
                target = $target
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
                target = ''
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

$expectedTargets = @('android-aarch64', 'android-armv7', 'coreelec-ne', 'coreelec-ng', 'libreelec-rpi4-aarch64', 'linux-x86_64', 'windows-x86_64')
$importedTargets = @($report | Where-Object { $_.imported } | ForEach-Object { $_.target })
$missingTargets = @($expectedTargets | Where-Object { $importedTargets -notcontains $_ } | Sort-Object)
if ($missingTargets.Count -gt 0) {
    throw "Missing imported targets: $($missingTargets -join ', ')"
}
