param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\repo.config.json'),
    [switch]$SkipRepositoryZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Resolve-ProjectPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')) $Path)
}

function New-Element([System.Xml.XmlDocument]$Document, [string]$Name, [string]$Text = $null) {
    $element = $Document.CreateElement($Name)
    if ($null -ne $Text) {
        $element.InnerText = $Text
    }
    return $element
}

function Save-XmlDocument([System.Xml.XmlDocument]$Document, [string]$Path) {
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $true
    $settings.NewLineChars = "`n"

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $Document.Save($writer)
    }
    finally {
        $writer.Close()
    }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-GzipCopy([string]$SourcePath, [string]$DestinationPath) {
    $source = [System.IO.File]::OpenRead($SourcePath)
    $target = [System.IO.File]::Create($DestinationPath)
    try {
        $gzip = [System.IO.Compression.GZipStream]::new($target, [System.IO.Compression.CompressionLevel]::Optimal)
        try {
            $source.CopyTo($gzip)
        }
        finally {
            $gzip.Dispose()
        }
    }
    finally {
        $source.Dispose()
        $target.Dispose()
    }
}

function Get-RelativeUnixPath([string]$BasePath, [string]$TargetPath) {
    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $baseFullPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFullPath += [System.IO.Path]::DirectorySeparatorChar
    }

    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = [System.Uri]::new($baseFullPath)
    $targetUri = [System.Uri]::new($targetFullPath)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())
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

function Add-OrReplaceTextChild(
    [System.Xml.XmlDocument]$Document,
    [System.Xml.XmlElement]$Parent,
    [string]$Name,
    [string]$Text
) {
    @($Parent.SelectNodes($Name)) | ForEach-Object {
        [void]$Parent.RemoveChild($_)
    }

    [void]$Parent.AppendChild((New-Element $Document $Name $Text))
}

function New-RepositoryAddonXml($Config, [string]$RepositoryDir) {
    $repo = $Config.repository
    $baseUrl = [string]$repo.baseUrl
    $baseUrl = $baseUrl.TrimEnd('/')

    $doc = [System.Xml.XmlDocument]::new()
    [void]$doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'UTF-8', $null))

    $addon = $doc.CreateElement('addon')
    $addon.SetAttribute('id', [string]$repo.id)
    $addon.SetAttribute('version', [string]$repo.version)
    $addon.SetAttribute('name', [string]$repo.name)
    $addon.SetAttribute('provider-name', [string]$repo.providerName)
    [void]$doc.AppendChild($addon)

    $requires = $doc.CreateElement('requires')
    $import = $doc.CreateElement('import')
    $import.SetAttribute('addon', 'xbmc.addon')
    $import.SetAttribute('version', '19.1.0')
    [void]$requires.AppendChild($import)
    [void]$addon.AppendChild($requires)

    $repoExtension = $doc.CreateElement('extension')
    $repoExtension.SetAttribute('point', 'xbmc.addon.repository')
    $repoExtension.SetAttribute('name', [string]$repo.name)

    foreach ($feed in $Config.feeds) {
        $path = ([string]$feed.path).Trim('/')
        $dir = $doc.CreateElement('dir')
        if ($feed.PSObject.Properties.Name -contains 'minversion') {
            $dir.SetAttribute('minversion', [string]$feed.minversion)
        }
        if ($feed.PSObject.Properties.Name -contains 'maxversion') {
            $dir.SetAttribute('maxversion', [string]$feed.maxversion)
        }

        $info = New-Element $doc 'info' "$baseUrl/$path/addons.xml"
        $info.SetAttribute('compressed', 'false')
        [void]$dir.AppendChild($info)
        [void]$dir.AppendChild((New-Element $doc 'checksum' "$baseUrl/$path/addons.xml.md5"))
        [void]$dir.AppendChild((New-Element $doc 'datadir' "$baseUrl/$path/"))
        [void]$dir.AppendChild((New-Element $doc 'hashes' ([string]$Config.hashes)))
        [void]$repoExtension.AppendChild($dir)
    }

    [void]$addon.AppendChild($repoExtension)

    $metadata = $doc.CreateElement('extension')
    $metadata.SetAttribute('point', 'xbmc.addon.metadata')
    foreach ($property in @('summary', 'description')) {
        foreach ($langProperty in $repo.$property.PSObject.Properties) {
            $element = New-Element $doc $property ([string]$langProperty.Value)
            $element.SetAttribute('lang', [string]$langProperty.Name)
            [void]$metadata.AppendChild($element)
        }
    }
    [void]$metadata.AppendChild((New-Element $doc 'platform' 'all'))
    [void]$metadata.AppendChild((New-Element $doc 'license' ([string]$repo.license)))
    [void]$metadata.AppendChild((New-Element $doc 'source' ([string]$repo.source)))
    [void]$addon.AppendChild($metadata)

    New-Item -ItemType Directory -Force -Path $RepositoryDir | Out-Null
    Save-XmlDocument $doc (Join-Path $RepositoryDir 'addon.xml')
}

function New-Feed($Feed, [string]$FeedDir) {
    New-Item -ItemType Directory -Force -Path $FeedDir | Out-Null

    $outDoc = [System.Xml.XmlDocument]::new()
    [void]$outDoc.AppendChild($outDoc.CreateXmlDeclaration('1.0', 'UTF-8', $null))
    $addonsRoot = $outDoc.CreateElement('addons')
    [void]$outDoc.AppendChild($addonsRoot)

    $zipFiles = Get-ChildItem -Path $FeedDir -Recurse -Filter '*.zip' -File |
        Where-Object { $_.Directory.Name -notmatch '^repository\.' } |
        Sort-Object FullName

    foreach ($zipFile in $zipFiles) {
        $addonXml = Get-AddonXmlFromZip $zipFile.FullName
        $addonDoc = [System.Xml.XmlDocument]::new()
        $addonDoc.PreserveWhitespace = $false
        $addonDoc.LoadXml($addonXml)

        $addon = $addonDoc.DocumentElement
        if ($addon.LocalName -ne 'addon') {
            throw "Root element in $($zipFile.FullName) is not <addon>"
        }

        $metadata = @($addon.SelectNodes('extension[@point="xbmc.addon.metadata"]')) | Select-Object -First 1
        if ($null -eq $metadata) {
            throw "Missing xbmc.addon.metadata extension in $($zipFile.FullName)"
        }

        $relativePath = Get-RelativeUnixPath $FeedDir $zipFile.FullName
        Add-OrReplaceTextChild $addonDoc $metadata 'size' ([string]$zipFile.Length)
        Add-OrReplaceTextChild $addonDoc $metadata 'path' $relativePath

        $imported = $outDoc.ImportNode($addon, $true)
        [void]$addonsRoot.AppendChild($imported)
    }

    $addonsPath = Join-Path $FeedDir 'addons.xml'
    $previousMd5 = if (Test-Path $addonsPath) {
        (Get-FileHash -Algorithm MD5 $addonsPath).Hash.ToLowerInvariant()
    }
    else {
        $null
    }

    Save-XmlDocument $outDoc $addonsPath

    $md5 = (Get-FileHash -Algorithm MD5 $addonsPath).Hash.ToLowerInvariant()
    Write-Utf8NoBom (Join-Path $FeedDir 'addons.xml.md5') $md5
    $gzipPath = Join-Path $FeedDir 'addons.xml.gz'
    if (($previousMd5 -ne $md5) -or -not (Test-Path $gzipPath)) {
        Write-GzipCopy $addonsPath $gzipPath
    }

    foreach ($zipFile in $zipFiles) {
        $sha256 = (Get-FileHash -Algorithm SHA256 $zipFile.FullName).Hash.ToLowerInvariant()
        Write-Utf8NoBom "$($zipFile.FullName).sha256" $sha256
    }
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

$repositoryDir = Join-Path $projectRoot ([string]$config.repository.id)
$repositoryAddonXml = Join-Path $repositoryDir 'addon.xml'
$previousRepositoryAddonHash = if (Test-Path $repositoryAddonXml) {
    (Get-FileHash -Algorithm SHA256 $repositoryAddonXml).Hash.ToLowerInvariant()
}
else {
    $null
}
New-RepositoryAddonXml $config $repositoryDir

foreach ($feed in $config.feeds) {
    $feedDir = Join-Path $projectRoot ([string]$feed.path)
    New-Feed $feed $feedDir
}

if (-not $SkipRepositoryZip) {
    $repositoryZip = Join-Path $repositoryDir "$($config.repository.id)-$($config.repository.version).zip"
    $repositoryAddonHash = (Get-FileHash -Algorithm SHA256 $repositoryAddonXml).Hash.ToLowerInvariant()
    if ((-not (Test-Path $repositoryZip)) -or ($previousRepositoryAddonHash -ne $repositoryAddonHash)) {
        if (Test-Path $repositoryZip) {
            Remove-Item -Force $repositoryZip
        }
        Compress-Archive -Path $repositoryDir -DestinationPath $repositoryZip -CompressionLevel Optimal
    }
    elseif (Test-Path $repositoryZip) {
        Write-Host "Repository add-on zip is already current."
    }
}

Write-Host "Repository metadata generated."
