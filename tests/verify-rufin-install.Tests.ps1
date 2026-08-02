[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $repositoryRoot "script/verify-rufin-install.ps1"
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "rufin-install-$([guid]::NewGuid())"

function Reset-Install {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Join-Path $temporaryRoot "bin") | Out-Null
    New-Item -ItemType File -Path (Join-Path $temporaryRoot "bin/rufin.exe") | Out-Null
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Operation,

        [Parameter(Mandatory)]
        [string] $Pattern
    )

    try {
        & $Operation
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Expected an error matching '$Pattern', received '$($_.Exception.Message)'"
        }
        return
    }

    throw "Expected an error matching '$Pattern'"
}

try {
    Reset-Install
    & $verifier -InstallDir $temporaryRoot -Version "0.11.1"

    Set-Content -LiteralPath (Join-Path $temporaryRoot "update-channel") -Value "direct" -NoNewline
    Assert-Throws -Pattern "did not record Scoop" -Operation {
        & $verifier -InstallDir $temporaryRoot -Version "0.11.1"
    }

    Reset-Install
    Assert-Throws -Pattern "update channel was not installed" -Operation {
        & $verifier -InstallDir $temporaryRoot -Version "0.11.2"
    }

    Set-Content -LiteralPath (Join-Path $temporaryRoot "update-channel") -Value "direct" -NoNewline
    Assert-Throws -Pattern "did not record Scoop" -Operation {
        & $verifier -InstallDir $temporaryRoot -Version "0.11.2"
    }

    Set-Content -LiteralPath (Join-Path $temporaryRoot "update-channel") -Value "scoop" -NoNewline
    & $verifier -InstallDir $temporaryRoot -Version "0.11.2"

    Write-Host "Rufin install verification tests passed"
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
