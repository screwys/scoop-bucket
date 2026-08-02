[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ReleasePath,

    [Parameter(Mandatory)]
    [string] $ManifestPath,

    [string] $ExpectedTag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-VersionParts {
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $match = [regex]::Match($Value, '^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.(?<patch>[0-9]+)$')
    if (-not $match.Success) {
        throw "Invalid Rufin version: $Value"
    }

    return @(
        [uint64]::Parse($match.Groups['major'].Value),
        [uint64]::Parse($match.Groups['minor'].Value),
        [uint64]::Parse($match.Groups['patch'].Value)
    )
}

function Compare-VersionParts {
    param(
        [Parameter(Mandatory)]
        [uint64[]] $Left,

        [Parameter(Mandatory)]
        [uint64[]] $Right
    )

    for ($index = 0; $index -lt 3; $index += 1) {
        if ($Left[$index] -lt $Right[$index]) {
            return -1
        }
        if ($Left[$index] -gt $Right[$index]) {
            return 1
        }
    }
    return 0
}

if (-not (Test-Path -LiteralPath $ReleasePath -PathType Leaf)) {
    throw "Rufin release metadata was not found: $ReleasePath"
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Rufin manifest was not found: $ManifestPath"
}

$release = Get-Content -Raw -LiteralPath $ReleasePath | ConvertFrom-Json
if ($release.draft -ne $false) {
    throw "The latest Rufin release is still a draft"
}
if ($release.prerelease -ne $false) {
    throw "The latest Rufin release is a prerelease"
}

$tag = [string] $release.tag_name
$tagMatch = [regex]::Match($tag, '^v(?<version>[0-9]+\.[0-9]+\.[0-9]+)$')
if (-not $tagMatch.Success) {
    throw "Invalid Rufin release tag: $tag"
}
if ($ExpectedTag -and $tag -cne $ExpectedTag) {
    throw "Expected Rufin release $ExpectedTag but received $tag"
}
$version = $tagMatch.Groups['version'].Value

$assetName = "Rufin-$version-setup.exe"
$assets = @($release.assets | Where-Object { $_.name -ceq $assetName })
if ($assets.Count -ne 1) {
    throw "Expected exactly one Rufin installer named $assetName, found $($assets.Count)"
}
$asset = $assets[0]
$expectedUrl = "https://github.com/screwys/Rufin/releases/download/$tag/$assetName"
if ([string] $asset.browser_download_url -cne $expectedUrl) {
    throw "The Rufin installer has an unexpected download URL"
}
if ([string] $asset.state -cne 'uploaded' -or [uint64] $asset.size -eq 0) {
    throw "The Rufin installer is not fully uploaded"
}

$digest = [string] $asset.digest
$digestMatch = [regex]::Match($digest, '^sha256:(?<hash>[0-9a-f]{64})$')
if (-not $digestMatch.Success) {
    throw "The Rufin installer does not have a valid SHA-256 digest"
}
$hash = $digestMatch.Groups['hash'].Value

$currentManifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$currentVersion = [string] $currentManifest.version
$targetParts = ConvertTo-VersionParts -Value $version
$currentParts = ConvertTo-VersionParts -Value $currentVersion
$versionComparison = Compare-VersionParts -Left $targetParts -Right $currentParts
if ($versionComparison -lt 0) {
    throw "Refusing to downgrade Rufin from $currentVersion to $version"
}
if (
    $versionComparison -eq 0 -and
    [string] $currentManifest.architecture.'64bit'.hash -cne $hash
) {
    throw "Refusing to change Rufin $version's installer digest without a version change"
}

$manifest = $currentManifest
$manifest.version = $version
$manifest.architecture.'64bit'.url = "$expectedUrl#/setup.exe"
$manifest.architecture.'64bit'.hash = $hash

$json = ($manifest | ConvertTo-Json -Depth 10).Replace("`r`n", "`n")
$json = [regex]::Replace($json, '(?m)^( +)', {
    param($match)
    return ' ' * ($match.Groups[1].Value.Length * 2)
})
$rendered = "$json`n"
$existing = Get-Content -Raw -LiteralPath $ManifestPath
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($ManifestPath),
    $rendered,
    [System.Text.UTF8Encoding]::new($false)
)

[pscustomobject] @{
    Hash = $hash
    Tag = $tag
    Version = $version
    Changed = $existing -cne $rendered
}
