<#
.SYNOPSIS
    TWMT Release Script - Automates version bump, build, and GitHub release creation.

.DESCRIPTION
    This script:
    1. Updates the version in pubspec.yaml
    2. Builds the Windows release
    3. Creates the installer with Inno Setup
    4. Creates a GitHub release with the installer attached

.PARAMETER Version
    The new version number (e.g., "1.2.0"). If not provided, will prompt.

.PARAMETER BuildNumber
    Optional build number. If not provided, auto-increments from current.

.PARAMETER Prerelease
    Mark this release as a pre-release on GitHub.

.PARAMETER Draft
    Create the GitHub release as a draft (not published).

.PARAMETER SkipBuild
    Skip the Flutter build step (useful if already built).

.PARAMETER SkipInstaller
    Skip installer creation (just create release with zip).

.EXAMPLE
    .\release.ps1 -Version "1.2.0"

.EXAMPLE
    .\release.ps1 -Version "1.3.0-beta" -Prerelease

.EXAMPLE
    .\release.ps1 -Version "2.0.0" -BuildNumber 100 -Draft
#>

param(
    [string]$Version,
    [int]$BuildNumber = 0,
    [switch]$Prerelease,
    [switch]$Draft,
    [switch]$SkipBuild,
    [switch]$SkipInstaller
)

# Configuration
$ErrorActionPreference = "Stop"

# Get project root (parent of scripts folder)
if ($PSScriptRoot) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
} else {
    $ProjectRoot = Get-Location
}

# Ensure we're in the project root
Set-Location $ProjectRoot

$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$BuildDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$InstallerDir = Join-Path $ProjectRoot "build\windows"
$AppName = "TWMT"

# Colors for output
function Write-Step { param($msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "    $msg" -ForegroundColor Gray }

# Banner
Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "       TWMT Release Script              " -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

# Check prerequisites
Write-Step "Checking prerequisites..."

# Check Flutter
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter is not installed or not in PATH"
    exit 1
}
Write-Success "Flutter found"

# Check GitHub CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) is not installed or not in PATH"
    Write-Info "Install from: https://cli.github.com/"
    exit 1
}
Write-Success "GitHub CLI found"

# Check gh auth status
$ghAuth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub CLI not authenticated. Run 'gh auth login' first."
    exit 1
}
Write-Success "GitHub CLI authenticated"

# Check pubspec.yaml exists
if (-not (Test-Path $PubspecPath)) {
    Write-Error "pubspec.yaml not found at: $PubspecPath"
    exit 1
}
Write-Success "pubspec.yaml found"

# Read current version from pubspec.yaml
Write-Step "Reading current version..."
$pubspecContent = Get-Content $PubspecPath -Raw
if ($pubspecContent -match 'version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
    $currentVersion = $Matches[1]
    $currentBuildNumber = [int]$Matches[2]
    Write-Info "Current version: $currentVersion+$currentBuildNumber"
} else {
    Write-Error "Could not parse version from pubspec.yaml"
    exit 1
}

# Prompt for version if not provided
if (-not $Version) {
    Write-Host ""
    Write-Host "Current version: " -NoNewline
    Write-Host "$currentVersion" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Enter new version (or press Enter to keep current): " -NoNewline -ForegroundColor Cyan
    $inputVersion = Read-Host

    if ($inputVersion) {
        $Version = $inputVersion
    } else {
        $Version = $currentVersion
    }
}

# Validate version format
if ($Version -notmatch '^\d+\.\d+\.\d+(-[\w\.]+)?$') {
    Write-Error "Invalid version format: $Version"
    Write-Info "Expected format: MAJOR.MINOR.PATCH (e.g., 1.2.0 or 1.2.0-beta.1)"
    exit 1
}

# Auto-increment build number if not provided
if ($BuildNumber -eq 0) {
    $BuildNumber = $currentBuildNumber + 1
}

$fullVersion = "$Version+$BuildNumber"
Write-Success "New version will be: $fullVersion"

# Confirm before proceeding
Write-Host ""
Write-Host "Release Configuration:" -ForegroundColor Yellow
Write-Host "  Version:     $Version"
Write-Host "  Build:       $BuildNumber"
Write-Host "  Tag:         v$Version"
Write-Host "  Prerelease:  $Prerelease"
Write-Host "  Draft:       $Draft"
Write-Host ""
Write-Host "Proceed with release? (Y/n): " -NoNewline -ForegroundColor Cyan
$confirm = Read-Host
if ($confirm -eq 'n' -or $confirm -eq 'N') {
    Write-Warning "Release cancelled by user"
    exit 0
}

# Step 1: Update pubspec.yaml
Write-Step "Updating pubspec.yaml..."
$newPubspecContent = $pubspecContent -replace 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $fullVersion"
Set-Content -Path $PubspecPath -Value $newPubspecContent -NoNewline
Write-Success "Version updated to $fullVersion"

# Step 2: Flutter clean and get dependencies
Write-Step "Cleaning and getting dependencies..."
flutter clean | Out-Null
flutter pub get | Out-Null
Write-Success "Dependencies updated"

# Step 3: Generate code (Riverpod, JSON serialization)
Write-Step "Generating code..."
dart run build_runner build --delete-conflicting-outputs 2>&1 | Out-Null
Write-Success "Code generation complete"

# Step 4: Build Windows release
if (-not $SkipBuild) {
    Write-Step "Building Windows release..."
    Write-Info "This may take a few minutes..."

    $buildOutput = flutter build windows --release 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter build failed"
        Write-Host $buildOutput
        exit 1
    }
    Write-Success "Windows build complete"
} else {
    Write-Warning "Skipping build step"
}

# Verify build output exists
if (-not (Test-Path $BuildDir)) {
    Write-Error "Build directory not found: $BuildDir"
    exit 1
}

# Step 5: Create installer or zip
$releaseAssets = @()

if (-not $SkipInstaller) {
    Write-Step "Creating installer with Inno Setup..."

    # Check if inno_bundle is available
    $innoOutput = dart run inno_bundle:build --release 2>&1
    if ($LASTEXITCODE -eq 0) {
        # Find the generated installer (search recursively)
        $installerPattern = Join-Path $InstallerDir "*.exe"
        $installers = Get-ChildItem -Path $InstallerDir -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -match "installer" -and $_.Name -notmatch "CompilerId" }

        if ($installers) {
            $installer = $installers | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $newInstallerName = "twmt-$Version-windows-x64-setup.exe"
            $newInstallerPath = Join-Path $InstallerDir $newInstallerName

            # Rename installer
            if ($installer.FullName -ne $newInstallerPath) {
                Copy-Item $installer.FullName $newInstallerPath -Force
            }

            $releaseAssets += $newInstallerPath
            Write-Success "Installer created: $newInstallerName"
        } else {
            Write-Warning "Installer not found, falling back to ZIP"
            $SkipInstaller = $true
        }
    } else {
        Write-Warning "Inno Setup failed, falling back to ZIP"
        Write-Info $innoOutput
        $SkipInstaller = $true
    }
}

# Always create a ZIP as backup/alternative
Write-Step "Creating ZIP archive..."
$zipName = "twmt-$Version-windows-x64.zip"
$zipPath = Join-Path $InstallerDir $zipName

# Remove old zip if exists
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

# Create zip from build directory
Compress-Archive -Path "$BuildDir\*" -DestinationPath $zipPath -Force
$releaseAssets += $zipPath
Write-Success "ZIP created: $zipName"

# Step 6: Set release notes (auto-generated)
$releaseNotesText = "Release version $Version"

# Step 7: Create GitHub release
Write-Step "Creating GitHub release..."

# Check if release already exists and delete it
$existingRelease = gh release view "v$Version" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Warning "Release v$Version already exists, deleting it..."
    gh release delete "v$Version" --yes
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Existing release deleted"
    } else {
        Write-Error "Failed to delete existing release"
        exit 1
    }
}

$ghArgs = @(
    "release", "create",
    "v$Version",
    "--title", "Version $Version"
)

# Add release notes
$notesFile = Join-Path $env:TEMP "release_notes_$Version.md"
Set-Content -Path $notesFile -Value $releaseNotesText
$ghArgs += "--notes-file"
$ghArgs += $notesFile

# Add flags
if ($Prerelease) {
    $ghArgs += "--prerelease"
}

if ($Draft) {
    $ghArgs += "--draft"
}

# Add assets
foreach ($asset in $releaseAssets) {
    if (Test-Path $asset) {
        $ghArgs += $asset
        Write-Info "Attaching: $(Split-Path $asset -Leaf)"
    }
}

Write-Info "Running: gh $($ghArgs -join ' ')"
Write-Host ""

# Execute gh release create
& gh @ghArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create GitHub release"

    # Cleanup notes file
    Remove-Item $notesFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# Cleanup notes file
Remove-Item $notesFile -Force -ErrorAction SilentlyContinue

# Step 8: Git commit version bump
Write-Step "Committing version bump..."
git add pubspec.yaml
git commit -m "chore: bump version to $Version"
git push

Write-Success "Version bump committed and pushed"

# Done!
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "     Release $Version Complete!        " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Release URL: " -NoNewline
gh release view "v$Version" --json url -q .url
Write-Host ""
Write-Host "Assets uploaded:"
foreach ($asset in $releaseAssets) {
    if (Test-Path $asset) {
        $size = (Get-Item $asset).Length / 1MB
        Write-Host "  - $(Split-Path $asset -Leaf) ($([math]::Round($size, 2)) MB)" -ForegroundColor Gray
    }
}
Write-Host ""
