# Release-ThinkSQL.ps1
# Builds, packages, and publishes a ThinkSQL release to GitHub
#
# Usage:
#   .\Release-ThinkSQL.ps1                      # Build + package only
#   .\Release-ThinkSQL.ps1 -Publish             # Build + package + create GitHub Release
#   .\Release-ThinkSQL.ps1 -Version "1.2.0"     # Override version (default: read from .psd1)
#
# Prerequisites:
#   - Go, GCC (for build)
#   - gh CLI (for -Publish only): https://cli.github.com/

param(
    [string]$Version,
    [switch]$Publish,
    [switch]$SkipBuild,
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$modulePath  = Join-Path $projectRoot "ThinkSQL-Module"
$psdPath     = Join-Path $modulePath  "ThinkSQL.psd1"
$releaseDir  = Join-Path $projectRoot "release"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ThinkSQL Release Builder" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── 1. Determine version ─────────────────────────────────────────────────────

$psdContent = Get-Content $psdPath -Raw

if (-not $Version) {
    if ($psdContent -match "ModuleVersion\s*=\s*'([^']+)'") {
        $Version = $Matches[1]
    } else {
        Write-Host "✗ Could not read version from $psdPath" -ForegroundColor Red
        exit 1
    }
}

$tag = "v$Version"
Write-Host "Version: $Version (tag: $tag)" -ForegroundColor Green
Write-Host ""

# ── 2. Build ─────────────────────────────────────────────────────────────────

if (-not $SkipBuild) {
    Write-Host "--- Building ThinkSQL.dll ---`n" -ForegroundColor Cyan

    Push-Location $projectRoot
    try {
        & "$projectRoot\Win-Build-ThinkSQL.ps1"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ Windows build failed" -ForegroundColor Red
            exit 1
        }
    }
    finally {
        Pop-Location
    }

    # Verify the DLL was copied into the module folder
    $moduleDll = Join-Path $modulePath "ThinkSQL.dll"
    if (-not (Test-Path $moduleDll)) {
        Write-Host "✗ ThinkSQL.dll missing from ThinkSQL-Module/" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
} else {
    Write-Host "Skipping build (using existing artifacts)`n" -ForegroundColor Yellow
}

# ── 3. Run tests ─────────────────────────────────────────────────────────────

if (-not $SkipTests) {
    Write-Host "--- Running Tests ---`n" -ForegroundColor Cyan

    $testScript = Join-Path $projectRoot "TestConnection\Test-DLL.ps1"
    if (Test-Path $testScript) {
        # Run tests in a child process so Add-Type doesn't pollute this session
        $testResult = & pwsh -NoProfile -File $testScript 2>&1
        $testResult | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n✗ Tests failed — aborting release" -ForegroundColor Red
            exit 1
        }
        Write-Host ""
    } else {
        Write-Host "⚠ Test script not found, skipping" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "Skipping tests`n" -ForegroundColor Yellow
}

# ── 4. Package release artifacts ──────────────────────────────────────────────

Write-Host "--- Packaging Release ---`n" -ForegroundColor Cyan

# Clean / create release directory
if (Test-Path $releaseDir) { Remove-Item $releaseDir -Recurse -Force }
New-Item $releaseDir -ItemType Directory | Out-Null

# --- PowerShell Module zip ---
$moduleZipName = "ThinkSQL-Module-v$Version.zip"
$moduleZipPath = Join-Path $releaseDir $moduleZipName
$moduleStagingDir = Join-Path $releaseDir "_staging_module"
$moduleStagingInner = Join-Path $moduleStagingDir "ThinkSQL"  # folder name = module name
New-Item $moduleStagingInner -ItemType Directory -Force | Out-Null

Copy-Item (Join-Path $modulePath "ThinkSQL.psd1") $moduleStagingInner
Copy-Item (Join-Path $modulePath "ThinkSQL.psm1") $moduleStagingInner
Copy-Item (Join-Path $modulePath "ThinkSQL.dll")  $moduleStagingInner
Copy-Item (Join-Path $modulePath "README.md")     $moduleStagingInner -ErrorAction SilentlyContinue
Copy-Item (Join-Path $projectRoot "LICENSE")       $moduleStagingInner -ErrorAction SilentlyContinue

Compress-Archive -Path "$moduleStagingInner" -DestinationPath $moduleZipPath
Remove-Item $moduleStagingDir -Recurse -Force

$moduleZipSize = [math]::Round((Get-Item $moduleZipPath).Length / 1MB, 2)
Write-Host "✓ $moduleZipName ($moduleZipSize MB)" -ForegroundColor Green

Write-Host "`nRelease artifacts in: $releaseDir" -ForegroundColor Gray
Write-Host ""

# ── 5. Generate release notes ────────────────────────────────────────────────

$releaseNotesPath = Join-Path $releaseDir "RELEASE_NOTES.md"

# Pull release notes from the .psd1 if available
$releaseNotes = ""
if ($psdContent -match "(?s)ReleaseNotes\s*=\s*@'(.*?)'@") {
    $releaseNotes = $Matches[1].Trim()
}

$releaseBody = @"
## ThinkSQL $tag

### Downloads

| Asset | Description |
|-------|-------------|
| ``$moduleZipName`` | PowerShell module — extract to a PSModulePath folder and ``Import-Module ThinkSQL`` |

### Quick Start — PowerShell Module

``````powershell
# Extract to your modules folder
Expand-Archive $moduleZipName -DestinationPath "`$env:USERPROFILE\Documents\PowerShell\Modules"

# Use it
Import-Module ThinkSQL
Connect-ThinkSQLConnection -Server localhost -Database master -Username sa -Password YourPassword
Invoke-ThinkSQL "SELECT @@VERSION AS Version"
Close-ThinkSQLConnection
``````

### Quick Start — C/C++ Interop

The module zip also contains ``ThinkSQL.dll`` and the header is generated at build time.

``````c
#include "ThinkSQL.h"
// Link against ThinkSQL.dll
char* err = ConnectDb("server=localhost;user id=sa;password=YourPassword;database=master");
char* json = ExecuteSql("SELECT @@VERSION AS Version");
FreeCString(json);
DisconnectDb();
``````

$(if ($releaseNotes) { "### Release Notes`n`n$releaseNotes" })
"@

$releaseBody | Set-Content -Path $releaseNotesPath -Encoding UTF8
Write-Host "✓ Release notes written to RELEASE_NOTES.md" -ForegroundColor Green
Write-Host ""

# ── 6. Publish to GitHub ─────────────────────────────────────────────────────

if ($Publish) {
    Write-Host "--- Publishing to GitHub ---`n" -ForegroundColor Cyan

    # Check gh CLI is available
    $ghVersionOutput = & gh --version 2>&1
    $ghExitCode = $LASTEXITCODE
    $ghVersion = ($ghVersionOutput | Select-Object -First 1)
    if ($ghExitCode -ne 0) {
        Write-Host "✗ GitHub CLI (gh) not found" -ForegroundColor Red
        Write-Host "  Install from: https://cli.github.com/" -ForegroundColor Gray
        exit 1
    }
    Write-Host "✓ $ghVersion" -ForegroundColor Green

    # Check auth
    $authOutput = & gh auth status 2>&1
    $authExitCode = $LASTEXITCODE
    if ($authExitCode -ne 0) {
        Write-Host "✗ Not authenticated with GitHub CLI" -ForegroundColor Red
        Write-Host "  Run: gh auth login" -ForegroundColor Gray
        exit 1
    }
    Write-Host "✓ Authenticated with GitHub" -ForegroundColor Green

    # Create git tag if it doesn't exist
    $existingTag = & git tag -l $tag 2>&1
    if ($existingTag -eq $tag) {
        Write-Host "✓ Tag $tag already exists" -ForegroundColor Green
    } else {
        Write-Host "  Creating tag $tag..." -ForegroundColor Yellow
        & git tag -a $tag -m "Release $tag"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ Failed to create tag" -ForegroundColor Red
            exit 1
        }
        & git push origin $tag
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ Failed to push tag" -ForegroundColor Red
            exit 1
        }
        Write-Host "✓ Tag $tag created and pushed" -ForegroundColor Green
    }

    # Create the GitHub release with assets
    Write-Host "  Creating GitHub Release..." -ForegroundColor Yellow

    & gh release create $tag `
        $moduleZipPath `
        --title "ThinkSQL $tag" `
        --notes-file $releaseNotesPath

    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to create release" -ForegroundColor Red
        exit 1
    }

    Write-Host "✓ GitHub Release $tag published!" -ForegroundColor Green
    Write-Host "  https://github.com/HealisticEngineer/thinksql/releases/tag/$tag" -ForegroundColor Gray
} else {
    Write-Host "--- Next Steps ---`n" -ForegroundColor Cyan
    Write-Host "Release artifacts are ready in ./release/" -ForegroundColor Yellow
    Write-Host "To publish to GitHub, run:" -ForegroundColor Yellow
    Write-Host "  .\Release-ThinkSQL.ps1 -Publish" -ForegroundColor White
    Write-Host "  .\Release-ThinkSQL.ps1 -Publish -SkipBuild -SkipTests  # reuse existing artifacts" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ Done!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
