param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\repo.config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Add-Problem([System.Collections.Generic.List[string]]$Problems, [string]$Message) {
    $Problems.Add($Message) | Out-Null
}

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

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$problems = [System.Collections.Generic.List[string]]::new()
$seen = @{}

if ([string]$config.repository.baseUrl -notmatch '^https://') {
    Add-Problem $problems "repository.baseUrl should use https://"
}

foreach ($feed in $config.feeds) {
    $feedDir = Join-Path $projectRoot ([string]$feed.path)
    if (-not (Test-Path $feedDir)) {
        Add-Problem $problems "Feed directory missing: $($feed.path)"
        continue
    }

    $zipFiles = Get-ChildItem -Path $feedDir -Recurse -Filter '*.zip' -File |
        Sort-Object FullName

    foreach ($zipFile in $zipFiles) {
        try {
            $addonDoc = [System.Xml.XmlDocument]::new()
            $addonDoc.LoadXml((Get-AddonXmlFromZip $zipFile.FullName))
            $addon = $addonDoc.DocumentElement

            if ($addon.LocalName -ne 'addon') {
                Add-Problem $problems "Root element in $($zipFile.FullName) is not <addon>"
                continue
            }

            $id = $addon.GetAttribute('id')
            $version = $addon.GetAttribute('version')
            $name = $addon.GetAttribute('name')
            $provider = $addon.GetAttribute('provider-name')

            foreach ($required in @($id, $version, $name, $provider)) {
                if ([string]::IsNullOrWhiteSpace($required)) {
                    Add-Problem $problems "Missing required addon attribute in $($zipFile.FullName)"
                    break
                }
            }

            if ($id -cnotmatch '^[a-z0-9._-]+$') {
                Add-Problem $problems "Invalid lowercase add-on id '$id' in $($zipFile.FullName)"
            }

            $expectedFile = "$id-$version.zip"
            if ($zipFile.Name -ne $expectedFile) {
                Add-Problem $problems "Zip file should be '$expectedFile': $($zipFile.FullName)"
            }

            $directoryName = $zipFile.Directory.Name
            if ($directoryName -notmatch "^$([regex]::Escape($id))\+(.+)$") {
                Add-Problem $problems "Directory should be '$id+platform': $($zipFile.Directory.FullName)"
                continue
            }

            $platformFromDir = $Matches[1]
            $metadata = @($addon.SelectNodes('extension[@point="xbmc.addon.metadata"]')) | Select-Object -First 1
            if ($null -eq $metadata) {
                Add-Problem $problems "Missing xbmc.addon.metadata extension in $($zipFile.FullName)"
                continue
            }

            $platformNode = @($metadata.SelectNodes('platform')) | Select-Object -First 1
            if ($null -eq $platformNode) {
                Add-Problem $problems "Missing platform tag in $($zipFile.FullName)"
            }
            elseif ($platformNode.InnerText.Trim() -ne $platformFromDir) {
                Add-Problem $problems "Platform '$($platformNode.InnerText.Trim())' does not match directory '$platformFromDir' in $($zipFile.FullName)"
            }

            if ($null -eq (@($addon.SelectNodes('extension[@point="kodi.pvrclient"]')) | Select-Object -First 1)) {
                Add-Problem $problems "Missing kodi.pvrclient extension in $($zipFile.FullName)"
            }

            foreach ($metadataChild in @('summary', 'description', 'license', 'source')) {
                if ($null -eq (@($metadata.SelectNodes($metadataChild)) | Select-Object -First 1)) {
                    Add-Problem $problems "Missing metadata <$metadataChild> in $($zipFile.FullName)"
                }
            }

            $key = "$($feed.path)|$id|$platformFromDir"
            if ($seen.ContainsKey($key)) {
                Add-Problem $problems "Duplicate add-on/platform in feed $($feed.path): $id $platformFromDir"
            }
            else {
                $seen[$key] = $true
            }
        }
        catch {
            Add-Problem $problems "Failed to validate $($zipFile.FullName): $($_.Exception.Message)"
        }
    }
}

if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Repository validation passed."
