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

function Test-ZipEntry([string]$ZipPath, [string]$EntryPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        return $null -ne ($zip.Entries | Where-Object { $_.FullName -eq $EntryPath } | Select-Object -First 1)
    }
    finally {
        $zip.Dispose()
    }
}

function Get-PackageRuleFromTarget([string]$Target) {
    switch ($Target) {
        'coreelec-ng' { return [pscustomobject]@{ expectedId = 'pvr.satip.coreelec-ng'; expectedPlatform = 'linux' } }
        'coreelec-ne' { return [pscustomobject]@{ expectedId = 'pvr.satip.coreelec-ne'; expectedPlatform = 'linux' } }
        'coreelec-no' { return [pscustomobject]@{ expectedId = 'pvr.satip.coreelec-no'; expectedPlatform = 'linux' } }
        'linux-x86_64' { return [pscustomobject]@{ expectedId = 'pvr.satip.linux-x86_64'; expectedPlatform = 'linux' } }
        'libreelec-rpi4-aarch64' { return [pscustomobject]@{ expectedId = 'pvr.satip.libreelec-rpi4-aarch64'; expectedPlatform = 'linux' } }
        'windows-x86_64' { return [pscustomobject]@{ expectedId = 'pvr.satip'; expectedPlatform = 'windows-x86_64' } }
        'android-aarch64' { return [pscustomobject]@{ expectedId = 'pvr.satip'; expectedPlatform = 'android-aarch64' } }
        'android-armv7' { return [pscustomobject]@{ expectedId = 'pvr.satip'; expectedPlatform = 'android-armv7' } }
        default { return $null }
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

            if (-not (Test-ZipEntry $zipFile.FullName "$id/addon.xml")) {
                Add-Problem $problems "ZIP root directory should match add-on id '$id': $($zipFile.FullName)"
            }

            $expectedFile = "$id-$version.zip"
            if ($zipFile.Name -ne $expectedFile) {
                Add-Problem $problems "Zip file should be '$expectedFile': $($zipFile.FullName)"
            }

            $target = $zipFile.Directory.Name
            $targetRule = Get-PackageRuleFromTarget $target

            $metadata = @($addon.SelectNodes('extension[@point="xbmc.addon.metadata"]')) | Select-Object -First 1
            if ($null -eq $metadata) {
                Add-Problem $problems "Missing xbmc.addon.metadata extension in $($zipFile.FullName)"
                continue
            }

            $platformNode = @($metadata.SelectNodes('platform')) | Select-Object -First 1
            $platform = ''
            if ($null -eq $platformNode) {
                Add-Problem $problems "Missing platform tag in $($zipFile.FullName)"
            }
            else {
                $platform = $platformNode.InnerText.Trim()
                if ([string]::IsNullOrWhiteSpace($platform)) {
                    Add-Problem $problems "Empty platform tag in $($zipFile.FullName)"
                }
                elseif ($null -ne $targetRule -and $platform -ne [string]$targetRule.expectedPlatform) {
                    Add-Problem $problems "Platform '$platform' does not match target '$target' expected platform '$($targetRule.expectedPlatform)' in $($zipFile.FullName)"
                }
            }

            if ($null -ne $targetRule -and $id -ne [string]$targetRule.expectedId) {
                Add-Problem $problems "Add-on id '$id' does not match target '$target' expected id '$($targetRule.expectedId)' in $($zipFile.FullName)"
            }

            if ($id -like 'pvr.satip*' -and $null -eq $targetRule) {
                Add-Problem $problems "pvr.satip package is stored in unknown target directory '$target': $($zipFile.FullName)"
            }

            if ($null -eq (@($addon.SelectNodes('extension[@point="kodi.pvrclient"]')) | Select-Object -First 1)) {
                Add-Problem $problems "Missing kodi.pvrclient extension in $($zipFile.FullName)"
            }

            if ($null -ne (@($addon.SelectNodes('extension[@point="xbmc.service"]')) | Select-Object -First 1)) {
                $pythonImport = @($addon.SelectNodes('requires/import[@addon="xbmc.python"]')) | Select-Object -First 1
                if ($null -eq $pythonImport) {
                    Add-Problem $problems "xbmc.service requires xbmc.python import in $($zipFile.FullName)"
                }
            }

            foreach ($metadataChild in @('summary', 'description', 'license', 'source')) {
                if ($null -eq (@($metadata.SelectNodes($metadataChild)) | Select-Object -First 1)) {
                    Add-Problem $problems "Missing metadata <$metadataChild> in $($zipFile.FullName)"
                }
            }

            $key = "$($feed.path)|$id|$version|$platform"
            if ($seen.ContainsKey($key)) {
                Add-Problem $problems "Duplicate add-on/version/platform in feed $($feed.path): $id $version $platform"
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
