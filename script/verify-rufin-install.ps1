[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $InstallDir,

    [Parameter(Mandatory)]
    [string] $Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "Invalid installed Rufin version: $Version"
}
if (-not (Test-Path -LiteralPath (Join-Path $InstallDir "bin/rufin.exe") -PathType Leaf)) {
    throw "The Rufin executable was not installed"
}

$channelPath = Join-Path $InstallDir "update-channel"
if (-not (Test-Path -LiteralPath $channelPath -PathType Leaf)) {
    if ($Version -cne "0.11.1") {
        throw "The Rufin update channel was not installed"
    }
    Write-Host "Rufin 0.11.1 predates the update channel marker"
    return
}
if ((Get-Content -Raw -LiteralPath $channelPath).Trim() -cne "scoop") {
    throw "Rufin did not record Scoop as its update channel"
}
