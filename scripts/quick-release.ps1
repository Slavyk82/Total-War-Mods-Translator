<#
.SYNOPSIS
    Quick release script - minimal prompts, uses defaults.

.DESCRIPTION
    Streamlined release for patch/minor updates.
    Automatically increments version based on type.

.PARAMETER Type
    Release type: patch, minor, or major

.EXAMPLE
    .\quick-release.ps1 patch    # 1.0.0 -> 1.0.1
    .\quick-release.ps1 minor    # 1.0.0 -> 1.1.0
    .\quick-release.ps1 major    # 1.0.0 -> 2.0.0
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("patch", "minor", "major")]
    [string]$Type
)

$ErrorActionPreference = "Stop"

# Get project root (parent of scripts folder)
if ($PSScriptRoot) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
} else {
    $ProjectRoot = Get-Location
}
Set-Location $ProjectRoot

$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"

# Read current version
$pubspecContent = Get-Content $PubspecPath -Raw
if ($pubspecContent -match 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]
    $build = [int]$Matches[4]
} else {
    Write-Host "[ERROR] Could not parse version" -ForegroundColor Red
    exit 1
}

# Calculate new version
switch ($Type) {
    "patch" { $patch++ }
    "minor" { $minor++; $patch = 0 }
    "major" { $major++; $minor = 0; $patch = 0 }
}

$newVersion = "$major.$minor.$patch"
$newBuild = $build + 1

Write-Host ""
Write-Host "Quick Release: $Type" -ForegroundColor Cyan
Write-Host "  Current: $($Matches[1]).$($Matches[2]).$($Matches[3])+$build"
Write-Host "  New:     $newVersion+$newBuild" -ForegroundColor Green
Write-Host ""

# Call main release script
$scriptPath = Join-Path $PSScriptRoot "release.ps1"
& $scriptPath -Version $newVersion -BuildNumber $newBuild
