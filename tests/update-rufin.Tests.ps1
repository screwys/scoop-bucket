[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$renderer = Join-Path $repositoryRoot "script/update-rufin.ps1"
$ownedManifestPath = Join-Path $repositoryRoot "bucket/rufin.json"
$fixtures = Join-Path $PSScriptRoot "fixtures"
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "rufin-manifest-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

function Copy-Fixture {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Destination
    )

    Copy-Item -LiteralPath (Join-Path $fixtures $Name) -Destination $Destination
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

function Invoke-RufinUninstaller {
    param(
        [Parameter(Mandatory)]
        [string] $Script,

        [Parameter(Mandatory)]
        [bool] $IsPurge
    )

    $cmd = "uninstall"
    $purge = $IsPurge
    $state = @{
        Arguments = @()
        Uninstalled = $false
    }

    function Test-Path {
        param([string] $Path)
        return -not $state.Uninstalled
    }

    function Start-Process {
        param(
            [string] $FilePath,
            [string[]] $ArgumentList,
            [switch] $Wait,
            [switch] $PassThru
        )

        $state.Arguments = @($ArgumentList)
        $state.Uninstalled = $true
        return [pscustomobject] @{ ExitCode = 0 }
    }

    function abort {
        param([string] $Message)
        throw $Message
    }

    Invoke-Command ([scriptblock]::Create($Script))
    return @($state.Arguments)
}

try {
    $manifestPath = Join-Path $temporaryRoot "rufin.json"
    Copy-Item -LiteralPath $ownedManifestPath -Destination $manifestPath
    $sourceManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $sourceManifest.version = "1.2.2"
    $sourceManifest.description = "Preserve this manifest-owned description"
    $sourceJson = $sourceManifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        $manifestPath,
        "$sourceJson`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    $result = & $renderer `
        -ReleasePath (Join-Path $fixtures "release-v1.2.3.json") `
        -ManifestPath $manifestPath `
        -ExpectedTag "v1.2.3"

    if (
        $result.Hash -cne ('a' * 64) -or
        $result.Tag -cne "v1.2.3" -or
        $result.Version -cne "1.2.3" -or
        -not $result.Changed
    ) {
        throw "The renderer returned the wrong release result"
    }
    $actual = (Get-Content -Raw $manifestPath).Replace("`r`n", "`n")
    $renderedManifest = $actual | ConvertFrom-Json
    if (
        $renderedManifest.architecture.'64bit'.url -cne
            "https://github.com/screwys/Rufin/releases/download/v1.2.3/Rufin-1.2.3-setup.exe#/setup.exe" -or
        $renderedManifest.architecture.'64bit'.hash -cne ('a' * 64)
    ) {
        throw "The renderer wrote the wrong Rufin installer"
    }
    if ($renderedManifest.description -cne $sourceManifest.description) {
        throw "The renderer overwrote a manifest-owned field"
    }

    $installerArgs = @($renderedManifest.installer.args)
    if (
        $installerArgs.Count -ne 2 -or
        $installerArgs[0] -cne "/S" -or
        $installerArgs[1] -cne "/RUFINCHANNEL=scoop"
    ) {
        throw "The Rufin installer is not marked as Scoop-managed"
    }
    $uninstallerScript = @($renderedManifest.uninstaller.script) -join "`n"
    if (
        $uninstallerScript -notmatch '\$purge' -or
        $uninstallerScript -notmatch '/PURGE'
    ) {
        throw "The Rufin uninstaller does not map Scoop purge requests"
    }
    $normalUninstallArgs = @(Invoke-RufinUninstaller -Script $uninstallerScript -IsPurge $false)
    if ($normalUninstallArgs.Count -ne 1 -or $normalUninstallArgs[0] -cne "/S") {
        throw "Normal Scoop uninstall unexpectedly purges Rufin data"
    }
    $purgeUninstallArgs = @(Invoke-RufinUninstaller -Script $uninstallerScript -IsPurge $true)
    if (
        $purgeUninstallArgs.Count -ne 2 -or
        $purgeUninstallArgs[0] -cne "/S" -or
        $purgeUninstallArgs[1] -cne "/PURGE"
    ) {
        throw "Scoop purge uninstall does not pass NSIS /PURGE"
    }

    $secondResult = & $renderer `
        -ReleasePath (Join-Path $fixtures "release-v1.2.3.json") `
        -ManifestPath $manifestPath `
        -ExpectedTag "v1.2.3"
    if ($secondResult.Changed) {
        throw "Rendering the same Rufin release was not idempotent"
    }

    $driftedManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $driftedManifest.architecture.'64bit'.hash = 'b' * 64
    $driftedJson = $driftedManifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        $manifestPath,
        "$driftedJson`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    Assert-Throws -Pattern "Refusing to change Rufin 1\.2\.3's installer digest" -Operation {
        & $renderer `
            -ReleasePath (Join-Path $fixtures "release-v1.2.3.json") `
            -ManifestPath $manifestPath `
            -ExpectedTag "v1.2.3"
    }

    Copy-Item -LiteralPath $ownedManifestPath -Destination $manifestPath -Force
    Assert-Throws -Pattern "exactly one Rufin installer" -Operation {
        & $renderer `
            -ReleasePath (Join-Path $fixtures "release-duplicate-installer.json") `
            -ManifestPath $manifestPath
    }

    Assert-Throws -Pattern "valid SHA-256 digest" -Operation {
        & $renderer `
            -ReleasePath (Join-Path $fixtures "release-invalid-digest.json") `
            -ManifestPath $manifestPath
    }

    Assert-Throws -Pattern "Expected Rufin release v1\.2\.4" -Operation {
        & $renderer `
            -ReleasePath (Join-Path $fixtures "release-v1.2.3.json") `
            -ManifestPath $manifestPath `
            -ExpectedTag "v1.2.4"
    }

    Copy-Fixture -Name "manifest-v2.0.0.json" -Destination $manifestPath
    Assert-Throws -Pattern "Refusing to downgrade Rufin" -Operation {
        & $renderer `
            -ReleasePath (Join-Path $fixtures "release-v1.2.3.json") `
            -ManifestPath $manifestPath
    }

    Write-Host "Rufin manifest renderer tests passed"
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
