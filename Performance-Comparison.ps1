# Performance-Comparison.ps1
# Compares performance between ThinkSQL module and SqlServer PowerShell module

param(
    [string]$Server = "localhost",
    [string]$Database = "master",
    [string]$Username = "sa",
    [string]$Password = "YourStrong!Passw0rd",
    [int]$Iterations = 100
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ThinkSQL vs SqlServer Module Performance Test" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Server: $Server" -ForegroundColor Gray
Write-Host "  Database: $Database" -ForegroundColor Gray
Write-Host "  Iterations: $Iterations`n" -ForegroundColor Gray

# Ensure SqlServer module is available
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "Installing SqlServer module..." -ForegroundColor Yellow
    Install-Module -Name SqlServer -Force -AllowClobber -Scope CurrentUser
}

Import-Module SqlServer -ErrorAction SilentlyContinue

# Import ThinkSQL module
$thinkSqlPath = Join-Path $PSScriptRoot "ThinkSQL-Module\ThinkSQL.psd1"
Import-Module $thinkSqlPath -Force

# Test queries
$testQueries = @{
    "Simple SELECT" = "SELECT @@VERSION AS Version"
    "System Query" = "SELECT name, database_id, create_date FROM sys.databases"
    "Aggregate Query" = "SELECT COUNT(*) AS TableCount FROM sys.tables"
}

# Results storage
$results = @{}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setting up test environment..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create test table for write operations
$setupConn = New-Object System.Data.SqlClient.SqlConnection
$setupConn.ConnectionString = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;Encrypt=False;TrustServerCertificate=True"
$setupConn.Open()

$setupCmd = $setupConn.CreateCommand()
$setupCmd.CommandText = @"
IF OBJECT_ID('PerfTestTable', 'U') IS NOT NULL 
    DROP TABLE PerfTestTable;
CREATE TABLE PerfTestTable (
    ID INT PRIMARY KEY IDENTITY(1,1),
    TestValue VARCHAR(100),
    CreatedAt DATETIME DEFAULT GETDATE()
);
"@
$setupCmd.ExecuteNonQuery() | Out-Null
$setupConn.Close()

Write-Host "[OK] Test table created`n" -ForegroundColor Green

# =============================================================================
# Test 1: ThinkSQL Module Performance
# =============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test 1: ThinkSQL Module" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Connect-ThinkSQLConnection -Server $Server -Database $Database -Username $Username -Password $Password

foreach ($queryName in $testQueries.Keys) {
    $query = $testQueries[$queryName]
    
    Write-Host "Testing: $queryName" -ForegroundColor Yellow
    Write-Host "  Query: $query" -ForegroundColor Gray
    
    $times = @()
    
    for ($i = 1; $i -le $Iterations; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-ThinkSQL $query
        $sw.Stop()
        $times += $sw.Elapsed.TotalMilliseconds
        
        if ($i -eq 1) {
            Write-Host "  First result count: $(if ($result -is [array]) { $result.Count } else { 1 })" -ForegroundColor Gray
        }
    }
    
    $avgTime = ($times | Measure-Object -Average).Average
    $minTime = ($times | Measure-Object -Minimum).Minimum
    $maxTime = ($times | Measure-Object -Maximum).Maximum
    
    Write-Host "  Average: $([math]::Round($avgTime, 2)) ms" -ForegroundColor Cyan
    Write-Host "  Min: $([math]::Round($minTime, 2)) ms" -ForegroundColor Gray
    Write-Host "  Max: $([math]::Round($maxTime, 2)) ms`n" -ForegroundColor Gray
    
    $results["ThinkSQL_$queryName"] = @{
        Average = $avgTime
        Min = $minTime
        Max = $maxTime
    }
}

# Test INSERT performance
Write-Host "Testing: Batch INSERTs" -ForegroundColor Yellow
$insertTimes = @()

for ($i = 1; $i -le $Iterations; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-ThinkSQL "INSERT INTO PerfTestTable (TestValue) VALUES ('ThinkSQL_$i')"
    $sw.Stop()
    $insertTimes += $sw.Elapsed.TotalMilliseconds
}

$avgInsert = ($insertTimes | Measure-Object -Average).Average
Write-Host "  Average INSERT: $([math]::Round($avgInsert, 2)) ms`n" -ForegroundColor Cyan

$results["ThinkSQL_INSERT"] = @{
    Average = $avgInsert
    Min = ($insertTimes | Measure-Object -Minimum).Minimum
    Max = ($insertTimes | Measure-Object -Maximum).Maximum
}

Close-ThinkSQLConnection

# =============================================================================
# Test 2: SqlServer Module Performance
# =============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test 2: SqlServer Module" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Clear test table
$setupConn.Open()
$setupCmd.CommandText = "TRUNCATE TABLE PerfTestTable"
$setupCmd.ExecuteNonQuery() | Out-Null
$setupConn.Close()

foreach ($queryName in $testQueries.Keys) {
    $query = $testQueries[$queryName]
    
    Write-Host "Testing: $queryName" -ForegroundColor Yellow
    Write-Host "  Query: $query" -ForegroundColor Gray
    
    $times = @()
    
    for ($i = 1; $i -le $Iterations; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Username $Username -Password $Password `
                                -Query $query -TrustServerCertificate -Encrypt Optional
        $sw.Stop()
        $times += $sw.Elapsed.TotalMilliseconds
        
        if ($i -eq 1) {
            Write-Host "  First result count: $(if ($result -is [array]) { $result.Count } else { 1 })" -ForegroundColor Gray
        }
    }
    
    $avgTime = ($times | Measure-Object -Average).Average
    $minTime = ($times | Measure-Object -Minimum).Minimum
    $maxTime = ($times | Measure-Object -Maximum).Maximum
    
    Write-Host "  Average: $([math]::Round($avgTime, 2)) ms" -ForegroundColor Cyan
    Write-Host "  Min: $([math]::Round($minTime, 2)) ms" -ForegroundColor Gray
    Write-Host "  Max: $([math]::Round($maxTime, 2)) ms`n" -ForegroundColor Gray
    
    $results["SqlServer_$queryName"] = @{
        Average = $avgTime
        Min = $minTime
        Max = $maxTime
    }
}

# Test INSERT performance
Write-Host "Testing: Batch INSERTs" -ForegroundColor Yellow
$insertTimes = @()

for ($i = 1; $i -le $Iterations; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Username $Username -Password $Password `
                  -Query "INSERT INTO PerfTestTable (TestValue) VALUES ('SqlServer_$i')" `
                  -TrustServerCertificate -Encrypt Optional
    $sw.Stop()
    $insertTimes += $sw.Elapsed.TotalMilliseconds
}

$avgInsert = ($insertTimes | Measure-Object -Average).Average
Write-Host "  Average INSERT: $([math]::Round($avgInsert, 2)) ms`n" -ForegroundColor Cyan

$results["SqlServer_INSERT"] = @{
    Average = $avgInsert
    Min = ($insertTimes | Measure-Object -Minimum).Minimum
    Max = ($insertTimes | Measure-Object -Maximum).Maximum
}

# =============================================================================
# Test 3: Raw ADO.NET Performance (Baseline)
# =============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test 3: Raw ADO.NET (Baseline)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Clear test table
$setupConn.Open()
$setupCmd.CommandText = "TRUNCATE TABLE PerfTestTable"
$setupCmd.ExecuteNonQuery() | Out-Null
$setupConn.Close()

$adoConn = New-Object System.Data.SqlClient.SqlConnection
$adoConn.ConnectionString = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;Encrypt=False;TrustServerCertificate=True"
$adoConn.Open()

foreach ($queryName in $testQueries.Keys) {
    $query = $testQueries[$queryName]
    
    Write-Host "Testing: $queryName" -ForegroundColor Yellow
    Write-Host "  Query: $query" -ForegroundColor Gray
    
    $times = @()
    
    for ($i = 1; $i -le $Iterations; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        $cmd = $adoConn.CreateCommand()
        $cmd.CommandText = $query
        $reader = $cmd.ExecuteReader()
        
        $rowCount = 0
        while ($reader.Read()) {
            $rowCount++
        }
        $reader.Close()
        
        $sw.Stop()
        $times += $sw.Elapsed.TotalMilliseconds
        
        if ($i -eq 1) {
            Write-Host "  First result count: $rowCount" -ForegroundColor Gray
        }
    }
    
    $avgTime = ($times | Measure-Object -Average).Average
    $minTime = ($times | Measure-Object -Minimum).Minimum
    $maxTime = ($times | Measure-Object -Maximum).Maximum
    
    Write-Host "  Average: $([math]::Round($avgTime, 2)) ms" -ForegroundColor Cyan
    Write-Host "  Min: $([math]::Round($minTime, 2)) ms" -ForegroundColor Gray
    Write-Host "  Max: $([math]::Round($maxTime, 2)) ms`n" -ForegroundColor Gray
    
    $results["ADO.NET_$queryName"] = @{
        Average = $avgTime
        Min = $minTime
        Max = $maxTime
    }
}

# Test INSERT performance
Write-Host "Testing: Batch INSERTs" -ForegroundColor Yellow
$insertTimes = @()

for ($i = 1; $i -le $Iterations; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $cmd = $adoConn.CreateCommand()
    $cmd.CommandText = "INSERT INTO PerfTestTable (TestValue) VALUES ('ADO.NET_$i')"
    $cmd.ExecuteNonQuery() | Out-Null
    $sw.Stop()
    $insertTimes += $sw.Elapsed.TotalMilliseconds
}

$avgInsert = ($insertTimes | Measure-Object -Average).Average
Write-Host "  Average INSERT: $([math]::Round($avgInsert, 2)) ms`n" -ForegroundColor Cyan

$results["ADO.NET_INSERT"] = @{
    Average = $avgInsert
    Min = ($insertTimes | Measure-Object -Minimum).Minimum
    Max = ($insertTimes | Measure-Object -Maximum).Maximum
}

$adoConn.Close()

# =============================================================================
# Results Summary
# =============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Performance Comparison Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Test Configuration:" -ForegroundColor Yellow
Write-Host "  Iterations per test: $Iterations" -ForegroundColor Gray
Write-Host "  All times in milliseconds`n" -ForegroundColor Gray

# Create comparison table
$comparisonData = @()

foreach ($queryName in $testQueries.Keys) {
    $thinkSqlAvg = $results["ThinkSQL_$queryName"].Average
    $sqlServerAvg = $results["SqlServer_$queryName"].Average
    $adoNetAvg = $results["ADO.NET_$queryName"].Average
    
    $speedup1 = [math]::Round($sqlServerAvg / $thinkSqlAvg, 2)
    $speedup2 = [math]::Round($adoNetAvg / $thinkSqlAvg, 2)
    
    $comparisonData += [PSCustomObject]@{
        Query = $queryName
        ThinkSQL = [math]::Round($thinkSqlAvg, 2)
        SqlServer = [math]::Round($sqlServerAvg, 2)
        "ADO.NET" = [math]::Round($adoNetAvg, 2)
        "ThinkSQL vs SqlServer" = "$($speedup1)x"
        "ThinkSQL vs ADO.NET" = "$($speedup2)x"
    }
}

# Add INSERT comparison
$thinkSqlInsert = $results["ThinkSQL_INSERT"].Average
$sqlServerInsert = $results["SqlServer_INSERT"].Average
$adoNetInsert = $results["ADO.NET_INSERT"].Average

$insertSpeedup1 = [math]::Round($sqlServerInsert / $thinkSqlInsert, 2)
$insertSpeedup2 = [math]::Round($adoNetInsert / $thinkSqlInsert, 2)

$comparisonData += [PSCustomObject]@{
    Query = "INSERT"
    ThinkSQL = [math]::Round($thinkSqlInsert, 2)
    SqlServer = [math]::Round($sqlServerInsert, 2)
    "ADO.NET" = [math]::Round($adoNetInsert, 2)
    "ThinkSQL vs SqlServer" = "$($insertSpeedup1)x"
    "ThinkSQL vs ADO.NET" = "$($insertSpeedup2)x"
}

$comparisonData | Format-Table -AutoSize

# Performance analysis
Write-Host "`nPerformance Analysis:" -ForegroundColor Yellow

$overallThinkSql = ($comparisonData | Measure-Object -Property ThinkSQL -Average).Average
$overallSqlServer = ($comparisonData | Measure-Object -Property SqlServer -Average).Average
$overallAdoNet = ($comparisonData | Measure-Object -Property "ADO.NET" -Average).Average

Write-Host "  Overall Average Times:" -ForegroundColor Cyan
Write-Host "    ThinkSQL:    $([math]::Round($overallThinkSql, 2)) ms" -ForegroundColor White
Write-Host "    SqlServer:   $([math]::Round($overallSqlServer, 2)) ms" -ForegroundColor White
Write-Host "    ADO.NET:     $([math]::Round($overallAdoNet, 2)) ms" -ForegroundColor White

$avgSpeedup = [math]::Round($overallSqlServer / $overallThinkSql, 2)
if ($avgSpeedup -gt 1) {
    Write-Host "`n  ThinkSQL is $($avgSpeedup)x faster than SqlServer module on average" -ForegroundColor Green
} elseif ($avgSpeedup -lt 1) {
    Write-Host "`n  SqlServer module is $([math]::Round(1/$avgSpeedup, 2))x faster than ThinkSQL on average" -ForegroundColor Yellow
} else {
    Write-Host "`n  Performance is roughly equivalent" -ForegroundColor White
}

$adoSpeedup = [math]::Round($overallThinkSql / $overallAdoNet, 2)
Write-Host "  ThinkSQL overhead vs raw ADO.NET: $($adoSpeedup)x" -ForegroundColor Gray

Write-Host "`nKey Findings:" -ForegroundColor Yellow
Write-Host "  • ThinkSQL uses persistent connection (faster for multiple queries)" -ForegroundColor Gray
Write-Host "  • SqlServer module creates new connection per Invoke-Sqlcmd call" -ForegroundColor Gray
Write-Host "  • ThinkSQL includes SNAPSHOT isolation for all SELECTs" -ForegroundColor Gray
Write-Host "  • ThinkSQL auto-processes CREATE TABLE statements" -ForegroundColor Gray
Write-Host "  • ADO.NET baseline shows raw .NET performance without overhead`n" -ForegroundColor Gray

# Cleanup
Write-Host "Cleaning up..." -ForegroundColor Yellow
$setupConn.Open()
$setupCmd.CommandText = "DROP TABLE PerfTestTable"
$setupCmd.ExecuteNonQuery() | Out-Null
$setupConn.Close()
Write-Host "[OK] Test table dropped`n" -ForegroundColor Green

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[COMPLETE] Performance Test Finished!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
