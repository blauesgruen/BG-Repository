param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [string]$ReleaseTag,

    [string]$FeedPath = 'omega',

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\repo.config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

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

function Get-ReleaseVersion([string]$Tag) {
    if ($Tag -match '(\d+\.\d+\.\d+)') {
        return $Matches[1]
    }

    return ''
}

function Get-ChannelFromAssetName([string]$AssetName) {
    if ($AssetName -match 'Amlogic-ng') {
        return 'coreelec-ng'
    }
    if ($AssetName -match 'Amlogic-ne') {
        return 'coreelec-ne'
    }
    if ($AssetName -match 'linux-x86_64') {
        return 'linux-x86_64'
    }
    if ($AssetName -match 'windows-(x64|x86_64)') {
        return 'windows-x86_64'
    }
    if ($AssetName -match 'android-aarch64') {
        return 'android-aarch64'
    }
    if ($AssetName -match 'android-armv7') {
        return 'android-armv7'
    }

    return ''
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI 'gh' is required for private release imports."
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$releaseVersion = Get-ReleaseVersion $ReleaseTag
$channelFeeds = @{}
foreach ($feed in $config.feeds) {
    if (($feed.PSObject.Properties.Name -contains 'channel') -and ([string]$feed.path).StartsWith($FeedPath.TrimEnd('/'))) {
        $channelFeeds[[string]$feed.channel] = $feed
    }
}

if ($channelFeeds.Count -eq 0) {
    throw "No channel feeds configured below '$FeedPath'."
}

$tempDir = Join-Path $env:TEMP ('kodi-release-import-' + [guid]::NewGuid().ToString('N'))
$ownerRepoName = ($Repository -replace '[^a-zA-Z0-9._-]+', '_')
$incomingDir = Join-Path $projectRoot "incoming\$ownerRepoName\$ReleaseTag"
$report = @()
$cleanedAddonIds = @{}

New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
New-Item -ItemType Directory -Force -Path $incomingDir | Out-Null

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
            $channel = Get-ChannelFromAssetName $zipFile.Name
            $feed = if ($channelFeeds.ContainsKey($channel)) { $channelFeeds[$channel] } else { $null }
            $expectedPlatform = if ($null -ne $feed -and ($feed.PSObject.Properties.Name -contains 'expectedPlatform')) {
                [string]$feed.expectedPlatform
            }
            else {
                ''
            }
            $reason = ''
            $imported = $false

            if ($addon.LocalName -ne 'addon') {
                $reason = 'root element is not addon'
            }
            elseif ($id -ne 'pvr.satip') {
                $reason = "unexpected addon id '$id'"
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
            elseif ([string]::IsNullOrWhiteSpace($channel)) {
                $reason = 'no channel rule matched asset name'
            }
            elseif ($null -eq $feed) {
                $reason = "no feed configured for channel '$channel'"
            }
            elseif (-not [string]::IsNullOrWhiteSpace($expectedPlatform) -and $platform -ne $expectedPlatform) {
                $reason = "platform '$platform' does not match channel '$channel' expected platform '$expectedPlatform'"
            }
            else {
                if (-not $cleanedAddonIds.ContainsKey($id)) {
                    foreach ($configuredFeed in $channelFeeds.Values) {
                        $configuredFeedDir = Join-Path $projectRoot ([string]$configuredFeed.path)
                        if (Test-Path $configuredFeedDir) {
                            Get-ChildItem -Path $configuredFeedDir -Directory -Filter $id |
                                Remove-Item -Recurse -Force
                        }
                    }
                    $cleanedAddonIds[$id] = $true
                }

                $feedDir = Join-Path $projectRoot ([string]$feed.path)
                $targetDir = Join-Path $feedDir $id
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
                channel = $channel
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
                channel = ''
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

$importedChannels = @($report | Where-Object { $_.imported } | ForEach-Object { $_.channel })
$missingChannels = @($channelFeeds.Keys | Where-Object { $importedChannels -notcontains $_ } | Sort-Object)
if ($missingChannels.Count -gt 0) {
    throw "Missing imported channels: $($missingChannels -join ', ')"
}
