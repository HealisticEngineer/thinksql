# Linux-Build-ThinkSQL.ps1
# This script compiles the ThinkSQL Go code into a Linux shared library (.so)
# Builds via WSL (Windows Subsystem for Linux) from Windows

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building ThinkSQL.so (Linux via WSL)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check WSL is available
Write-Host "Checking for WSL..." -ForegroundColor Yellow
$wslCheck = & wsl --status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ WSL is not installed or not running" -ForegroundColor Red
    Write-Host "  Install with: wsl --install" -ForegroundColor Gray
    exit 1
}
Write-Host "✓ WSL is available" -ForegroundColor Green

# Check Go is installed in WSL
Write-Host "Checking for Go in WSL..." -ForegroundColor Yellow
$wslGoVersion = & wsl bash -c "go version 2>&1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Go is not installed in WSL" -ForegroundColor Red
    Write-Host "  Install in WSL with:" -ForegroundColor Gray
    Write-Host "    sudo apt update && sudo apt install -y golang-go" -ForegroundColor Gray
    Write-Host "    or download from https://golang.org/dl/" -ForegroundColor Gray
    exit 1
}
Write-Host "✓ Go found in WSL: $wslGoVersion" -ForegroundColor Green

# Check GCC is installed in WSL
Write-Host "Checking for GCC in WSL..." -ForegroundColor Yellow
$wslGccVersion = & wsl bash -c "set -o pipefail; gcc --version 2>&1 | head -1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ GCC is not installed in WSL" -ForegroundColor Red
    Write-Host "  Install with: sudo apt install -y build-essential" -ForegroundColor Gray
    exit 1
}
Write-Host "✓ GCC found in WSL: $wslGccVersion" -ForegroundColor Green
Write-Host ""

# Convert Windows path to WSL path
$winPath = (Get-Location).Path.Replace('\', '\\')
$wslPath = & wsl wslpath -u $winPath
Write-Host "Working directory: $wslPath" -ForegroundColor Gray

# Clean old build artifacts
Write-Host "Cleaning old build artifacts..." -ForegroundColor Yellow
if (Test-Path "ThinkSQL.so") {
    Remove-Item "ThinkSQL.so" -Force
    Write-Host "  Removed old ThinkSQL.so" -ForegroundColor Gray
}

# Build inside WSL
Write-Host ""
Write-Host "Building shared library with CGO in WSL..." -ForegroundColor Yellow

$buildScript = "cd '$wslPath' && CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -buildmode=c-shared -ldflags='-s -w' -o ThinkSQL.so main.go 2>&1"

$buildOutput = & wsl bash -c $buildScript
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Build failed" -ForegroundColor Red
    Write-Host $buildOutput -ForegroundColor Red
    exit 1
}

# Verify build artifacts
Write-Host "✓ Build completed successfully" -ForegroundColor Green
Write-Host ""

if (Test-Path "ThinkSQL.so") {
    $soSize = [math]::Round((Get-Item "ThinkSQL.so").Length / 1MB, 2)
    Write-Host "✓ ThinkSQL.so created ($soSize MB)" -ForegroundColor Green
}
else {
    Write-Host "✗ ThinkSQL.so not found" -ForegroundColor Red
    exit 1
}

if (Test-Path "ThinkSQL.h") {
    Write-Host "✓ ThinkSQL.h created (C header file)" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ Linux Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Usage on Linux:" -ForegroundColor Yellow
Write-Host "  Copy ThinkSQL.so and ThinkSQL.h to your Linux machine" -ForegroundColor Gray
Write-Host "  Load with: dlopen(""./ThinkSQL.so"", RTLD_LAZY)" -ForegroundColor Gray
Write-Host "  Or from PowerShell: Add-Type with [DllImport(""./ThinkSQL.so"")]" -ForegroundColor Gray
