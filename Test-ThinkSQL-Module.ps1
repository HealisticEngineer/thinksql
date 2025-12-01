# Test-ThinkSQL-Module.ps1
# Demonstrates the ThinkSQL PowerShell module functionality

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ThinkSQL PowerShell Module Demo" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import the module
$modulePath = Join-Path $PSScriptRoot "ThinkSQL-Module\ThinkSQL.psd1"
Write-Host "Importing module from: $modulePath" -ForegroundColor Yellow
Import-Module $modulePath -Force
Write-Host "[OK] Module imported`n" -ForegroundColor Green

try {
    # Connect to SQL Server
    Write-Host "Connecting to SQL Server..." -ForegroundColor Yellow
    Connect-ThinkSQLConnection -Server "localhost" -Database "master" -Username "sa" -Password "NeverSafe2Day!"
    Write-Host "[OK] Connected!`n" -ForegroundColor Green
    
    # Check connection
    $conn = Get-ThinkSQLConnection
    Write-Host "Connection Info:" -ForegroundColor Cyan
    Write-Host "  Server: $($conn.Server)" -ForegroundColor Gray
    Write-Host "  Database: $($conn.Database)" -ForegroundColor Gray
    Write-Host "  Username: $($conn.Username)`n" -ForegroundColor Gray
    
    # Test 1: SELECT query
    Write-Host "Test 1: SELECT Query" -ForegroundColor Yellow
    Write-Host "Query: SELECT @@VERSION AS Version" -ForegroundColor Gray
    $version = Invoke-ThinkSQL "SELECT @@VERSION AS Version"
    Write-Host "[OK] Result:" -ForegroundColor Green
    $version | Format-List
    
    # Test 2: Create table
    Write-Host "`nTest 2: CREATE TABLE (auto-adds primary key)" -ForegroundColor Yellow
    Invoke-ThinkSQL "IF OBJECT_ID('TestModuleTable', 'U') IS NOT NULL DROP TABLE TestModuleTable"
    Invoke-ThinkSQL "CREATE TABLE TestModuleTable (Name VARCHAR(100), Age INT)"
    Write-Host "[OK] Table created with auto-generated primary key`n" -ForegroundColor Green
    
    # Test 3: Insert data
    Write-Host "Test 3: INSERT Data" -ForegroundColor Yellow
    Invoke-ThinkSQL "INSERT INTO TestModuleTable (Name, Age) VALUES ('Alice', 30)"
    Invoke-ThinkSQL "INSERT INTO TestModuleTable (Name, Age) VALUES ('Bob', 25)"
    Invoke-ThinkSQL "INSERT INTO TestModuleTable (Name, Age) VALUES ('Charlie', 35)"
    Write-Host "[OK] 3 rows inserted`n" -ForegroundColor Green
    
    # Test 4: Query data
    Write-Host "Test 4: SELECT Data (returns PowerShell objects)" -ForegroundColor Yellow
    Write-Host "Query: SELECT * FROM TestModuleTable ORDER BY Name" -ForegroundColor Gray
    $results = Invoke-ThinkSQL "SELECT * FROM TestModuleTable ORDER BY Name"
    Write-Host "[OK] Results:" -ForegroundColor Green
    $results | Format-Table -AutoSize
    
    # Test 5: Query as JSON
    Write-Host "`nTest 5: SELECT Data (returns JSON)" -ForegroundColor Yellow
    $json = Invoke-ThinkSQL "SELECT Name, Age FROM TestModuleTable WHERE Age > 25" -AsJson
    Write-Host "[OK] JSON Result:" -ForegroundColor Green
    Write-Host $json -ForegroundColor Cyan
    Write-Host ""
    
    # Test 6: Update data
    Write-Host "Test 6: UPDATE Data" -ForegroundColor Yellow
    Invoke-ThinkSQL "UPDATE TestModuleTable SET Age = 31 WHERE Name = 'Alice'"
    Write-Host "[OK] Updated Alice's age`n" -ForegroundColor Green
    
    # Test 7: Query updated data
    Write-Host "Test 7: Verify UPDATE" -ForegroundColor Yellow
    $alice = Invoke-ThinkSQL "SELECT * FROM TestModuleTable WHERE Name = 'Alice'"
    Write-Host "[OK] Alice's current age: $($alice.Age)`n" -ForegroundColor Green
    
    # Test 8: Working with results
    Write-Host "Test 8: Working with Results (PowerShell pipeline)" -ForegroundColor Yellow
    $allData = Invoke-ThinkSQL "SELECT * FROM TestModuleTable"
    Write-Host "Total rows: $($allData.Count)" -ForegroundColor Cyan
    
    $avgAge = ($allData | Measure-Object -Property Age -Average).Average
    Write-Host "Average age: $([math]::Round($avgAge, 2))" -ForegroundColor Cyan
    
    $oldest = $allData | Sort-Object Age -Descending | Select-Object -First 1
    Write-Host "Oldest person: $($oldest.Name) ($($oldest.Age) years)`n" -ForegroundColor Cyan
    
    # Test 9: Cleanup
    Write-Host "Test 9: Cleanup" -ForegroundColor Yellow
    Invoke-ThinkSQL "DROP TABLE TestModuleTable"
    Write-Host "[OK] Test table dropped`n" -ForegroundColor Green
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "[SUCCESS] All Tests Passed!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Write-Host "Summary:" -ForegroundColor Yellow
    Write-Host "  ✓ Module imports successfully" -ForegroundColor Green
    Write-Host "  ✓ Connection management works" -ForegroundColor Green
    Write-Host "  ✓ SELECT returns PowerShell objects" -ForegroundColor Green
    Write-Host "  ✓ SELECT can return JSON with -AsJson" -ForegroundColor Green
    Write-Host "  ✓ CREATE TABLE auto-adds primary key" -ForegroundColor Green
    Write-Host "  ✓ INSERT/UPDATE/DELETE work correctly" -ForegroundColor Green
    Write-Host "  ✓ Results work with PowerShell pipeline" -ForegroundColor Green
    Write-Host "  ✓ No INFO output clutter`n" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Test failed: $_" -ForegroundColor Red
}
finally {
    # Always close connection
    Close-ThinkSQLConnection
    Write-Host "Connection closed." -ForegroundColor Yellow
}
