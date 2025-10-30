# Build-ThinkSQL.ps1
# This script compiles the ThinkSQL Go code into a Windows DLL

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building ThinkSQL.dll" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check for Go
Write-Host "Checking for Go..." -ForegroundColor Yellow
$goVersion = & go version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Go is not installed or not in PATH" -ForegroundColor Red
    Write-Host "  Please install Go from https://golang.org/dl/" -ForegroundColor Gray
    exit 1
}
Write-Host "✓ Go found: $goVersion" -ForegroundColor Green

# Check for GCC
Write-Host "Checking for GCC (required for CGO)..." -ForegroundColor Yellow
$gccVersion = & gcc --version 2>&1 | Select-Object -First 1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ GCC is not installed or not in PATH" -ForegroundColor Red
    Write-Host "  Installing GCC via winget..." -ForegroundColor Yellow
    
    try {
        winget install -e --id BrechtSanders.WinLibs.MCF.UCRT --silent
        Write-Host "✓ GCC installed successfully" -ForegroundColor Green
        Write-Host "  Please restart your PowerShell session and run this script again" -ForegroundColor Yellow
        exit 0
    }
    catch {
        Write-Host "✗ Failed to install GCC" -ForegroundColor Red
        Write-Host "  Please manually install MinGW-w64 from https://winlibs.com/" -ForegroundColor Gray
        exit 1
    }
}
Write-Host "✓ GCC found: $gccVersion" -ForegroundColor Green
Write-Host ""


# Clean old build artifacts
Write-Host "Cleaning old build artifacts..." -ForegroundColor Yellow
if (Test-Path "ThinkSQL.dll") {
    Remove-Item "ThinkSQL.dll" -Force
    Write-Host "  Removed old ThinkSQL.dll" -ForegroundColor Gray
}
if (Test-Path "ThinkSQL.h") {
    Remove-Item "ThinkSQL.h" -Force
    Write-Host "  Removed old ThinkSQL.h" -ForegroundColor Gray
}

# Enable CGO and build
Write-Host ""
Write-Host "Building DLL with CGO..." -ForegroundColor Yellow
$env:CGO_ENABLED = "1"

$buildOutput = & go build -buildmode=c-shared -o ThinkSQL.dll main.go 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Build failed" -ForegroundColor Red
    Write-Host $buildOutput -ForegroundColor Red
    exit 1
}

# Verify build artifacts
Write-Host "✓ Build completed successfully" -ForegroundColor Green
Write-Host ""

if (Test-Path "ThinkSQL.dll") {
    $dllSize = [math]::Round((Get-Item "ThinkSQL.dll").Length / 1MB, 2)
    Write-Host "✓ ThinkSQL.dll created ($dllSize MB)" -ForegroundColor Green
}
else {
    Write-Host "✗ ThinkSQL.dll not found" -ForegroundColor Red
    exit 1
}

if (Test-Path "ThinkSQL.h") {
    Write-Host "✓ ThinkSQL.h created (C header file)" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run .\TestConnection\Test-DLL-Import.ps1 to test DLL loading" -ForegroundColor Gray
Write-Host "  2. Run .\TestConnection\Test-SQL-Connection.ps1 to test SQL connection" -ForegroundColor Gray
