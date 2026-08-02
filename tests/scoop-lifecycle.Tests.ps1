[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ScoopPath
)

# Scoop treats absent configuration properties as null during startup.
Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$scoopRoot = (Resolve-Path -LiteralPath $ScoopPath).Path
. (Join-Path $scoopRoot "lib/core.ps1")
. (Join-Path $scoopRoot "lib/manifest.ps1")
. (Join-Path $scoopRoot "lib/install.ps1")

function Invoke-ScoopUninstallHook {
    param(
        [Parameter(Mandatory)]
        [string] $Command,

        [Parameter(Mandatory)]
        [bool] $Purge
    )

    $cmd = $Command
    $purge = $Purge
    $manifest = [pscustomobject] @{
        uninstaller = [pscustomobject] @{
            script = @(
                '[pscustomobject] @{ Command = $cmd; Purge = [bool] $purge }'
            )
        }
    }

    $results = @(Invoke-HookScript `
        -HookType uninstaller `
        -Manifest $manifest `
        -ProcessorArchitecture 64bit)
    return @($results | Where-Object { $_ -is [pscustomobject] })
}

$normal = @(Invoke-ScoopUninstallHook -Command uninstall -Purge $false)
$purged = @(Invoke-ScoopUninstallHook -Command uninstall -Purge $true)
if ($normal.Count -ne 1 -or $purged.Count -ne 1) {
    throw "Scoop did not run the manifest uninstaller hook"
}
if ($normal[0].Command -cne "uninstall" -or $normal[0].Purge) {
    throw "Scoop exposed the wrong normal uninstall lifecycle"
}
if ($purged[0].Command -cne "uninstall" -or -not $purged[0].Purge) {
    throw "Scoop did not expose its purge request to the manifest"
}

Write-Host "Scoop uninstall lifecycle tests passed"
