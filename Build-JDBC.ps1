# Build-JDBC.ps1
# Builds the ThinkSQL JDBC driver JAR using Maven

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building ThinkSQL JDBC Driver" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check for Java
Write-Host "Checking for Java..." -ForegroundColor Yellow
$javaVersion = & java -version 2>&1 | Select-Object -First 1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Java is not installed or not in PATH" -ForegroundColor Red
    Write-Host "  Please install JDK 11+ from https://adoptium.net/" -ForegroundColor Gray
    exit 1
}
Write-Host "✓ Java found: $javaVersion" -ForegroundColor Green

# Check for Maven
Write-Host "Checking for Maven..." -ForegroundColor Yellow
$mvnVersion = & mvn --version 2>&1 | Select-Object -First 1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Maven is not installed or not in PATH" -ForegroundColor Red
    Write-Host "  Installing Maven via winget..." -ForegroundColor Yellow

    try {
        winget install -e --id Apache.Maven --silent
        Write-Host "✓ Maven installed successfully" -ForegroundColor Green
        Write-Host "  Please restart your PowerShell session and run this script again" -ForegroundColor Yellow
        exit 0
    }
    catch {
        Write-Host "✗ Failed to install Maven" -ForegroundColor Red
        Write-Host "  Please manually install Maven from https://maven.apache.org/download.cgi" -ForegroundColor Gray
        exit 1
    }
}
Write-Host "✓ Maven found: $mvnVersion" -ForegroundColor Green
Write-Host ""

# Navigate to the JDBC module directory
$jdbcDir = Join-Path $PSScriptRoot "ThinkSQL-JDBC"
Push-Location $jdbcDir

try {
    # Clean and build
    Write-Host "Building JAR with Maven..." -ForegroundColor Yellow
    $buildOutput = & mvn clean package -q 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Build failed" -ForegroundColor Red
        Write-Host $buildOutput -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Build completed successfully" -ForegroundColor Green
    Write-Host ""

    # Find the built JAR
    $jarFile = Get-ChildItem -Path "target" -Filter "thinksql-jdbc-*.jar" |
        Where-Object { $_.Name -notlike "*-sources.jar" -and $_.Name -notlike "*-javadoc.jar" } |
        Select-Object -First 1
    if ($jarFile) {
        $jarSize = [math]::Round($jarFile.Length / 1KB, 1)
        Write-Host "✓ $($jarFile.Name) created ($jarSize KB)" -ForegroundColor Green

        # Copy to project root for easy access
        Copy-Item $jarFile.FullName -Destination $PSScriptRoot -Force
        Write-Host "✓ JAR copied to project root" -ForegroundColor Green
    }
    else {
        Write-Host "✗ JAR file not found in target/" -ForegroundColor Red
        exit 1
    }

    # Copy native library into the JAR directory for convenience
    $dllPath = Join-Path $PSScriptRoot "ThinkSQL.dll"
    $soPath = Join-Path $PSScriptRoot "ThinkSQL.so"

    if (Test-Path $dllPath) {
        Copy-Item $dllPath -Destination "target/" -Force
        Write-Host "✓ ThinkSQL.dll copied to target/ for testing" -ForegroundColor Green
    }
    if (Test-Path $soPath) {
        Copy-Item $soPath -Destination "target/" -Force
        Write-Host "✓ ThinkSQL.so copied to target/ for testing" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ JDBC Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "  java --enable-native-access=ALL-UNNAMED -Dthinksql.library.path=. -cp thinksql-jdbc-1.0.0.jar com.thinksql.jdbc.example.ThinkSQLExample" -ForegroundColor Gray
Write-Host ""
Write-Host "JDBC URL format:" -ForegroundColor Yellow
Write-Host '  jdbc:thinksql:server=localhost;user id=sa;password=YourPass;database=master' -ForegroundColor Gray
