# Test-Module.ps1
# Comprehensive test suite for the ThinkSQL PowerShell module
# Tests: Import, connection management, SELECT, CREATE TABLE, INSERT, UPDATE, DELETE,
#        DECLARE, WITH (CTE), JSON output, pipeline integration

param(
    [string]$Server = "localhost",
    [string]$Database = "master",
    [string]$Username = "SA",
    [string]$Password = "NeverSafe2Day!"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ThinkSQL Module — Full Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── Module Import ────────────────────────────────────────────────────────────

$modulePath = Join-Path $PSScriptRoot "..\ThinkSQL-Module\ThinkSQL.psd1"
Write-Host "Module: $modulePath" -ForegroundColor Gray
Write-Host "Server: $Server | Database: $Database`n" -ForegroundColor Gray

$script:passed = 0
$script:failed = 0

function Assert-Pass { param([string]$Name) Write-Host "  [PASS] $Name" -ForegroundColor Green; $script:passed++ }
function Assert-Fail { param([string]$Name, [string]$Detail) Write-Host "  [FAIL] $Name — $Detail" -ForegroundColor Red; $script:failed++ }

# =============================================================================
# SECTION 1: Module Import
# =============================================================================

Write-Host "--- 1. Module Import ---`n" -ForegroundColor Cyan

try {
    Import-Module $modulePath -Force -ErrorAction Stop
    Assert-Pass "Module imported"
}
catch {
    Assert-Fail "Module import" "$_"
    exit 1
}

# Verify exported commands
$commands = Get-Command -Module ThinkSQL | Select-Object -ExpandProperty Name
foreach ($expected in @("Connect-ThinkSQLConnection", "Close-ThinkSQLConnection", "Get-ThinkSQLConnection", "Invoke-ThinkSQL")) {
    if ($commands -contains $expected) {
        Assert-Pass "Export: $expected"
    } else {
        Assert-Fail "Export: $expected" "not found"
    }
}
Write-Host ""

# =============================================================================
# SECTION 2: Connection Management
# =============================================================================

Write-Host "--- 2. Connection Management ---`n" -ForegroundColor Cyan

try {
    Connect-ThinkSQLConnection -Server $Server -Database $Database -Username $Username -Password $Password
    Assert-Pass "Connect-ThinkSQLConnection"

    $conn = Get-ThinkSQLConnection
    if ($conn.Server -eq $Server -and $conn.Database -eq $Database) {
        Assert-Pass "Get-ThinkSQLConnection returns correct info"
    } else {
        Assert-Fail "Get-ThinkSQLConnection" "unexpected values"
    }
}
catch {
    Assert-Fail "Connection" "$_"
    exit 1
}
Write-Host ""

# =============================================================================
# SECTION 3: Basic SELECT
# =============================================================================

Write-Host "--- 3. Basic SELECT ---`n" -ForegroundColor Cyan

try {
    $version = Invoke-ThinkSQL "SELECT @@VERSION AS Version"
    if ($version -and $version.Version) {
        Assert-Pass "SELECT @@VERSION"
    } else {
        Assert-Fail "SELECT @@VERSION" "no result"
    }
}
catch { Assert-Fail "SELECT @@VERSION" "$_" }

try {
    $dbs = Invoke-ThinkSQL "SELECT name, database_id FROM sys.databases"
    if ($dbs.Count -ge 1) {
        Assert-Pass "SELECT sys.databases ($($dbs.Count) rows)"
    } else {
        Assert-Fail "SELECT sys.databases" "no rows"
    }
}
catch { Assert-Fail "SELECT sys.databases" "$_" }

try {
    $now = Invoke-ThinkSQL "SELECT GETDATE() AS Now"
    if ($now.Now) {
        Assert-Pass "SELECT GETDATE()"
    } else {
        Assert-Fail "SELECT GETDATE()" "no result"
    }
}
catch { Assert-Fail "SELECT GETDATE()" "$_" }
Write-Host ""

# =============================================================================
# SECTION 4: JSON Output (-AsJson)
# =============================================================================

Write-Host "--- 4. JSON Output ---`n" -ForegroundColor Cyan

try {
    $json = Invoke-ThinkSQL "SELECT 1 AS A, 2 AS B" -AsJson
    $parsed = $json | ConvertFrom-Json
    if ($parsed.A -eq 1 -and $parsed.B -eq 2) {
        Assert-Pass "-AsJson returns valid JSON"
    } else {
        Assert-Fail "-AsJson" "unexpected values"
    }
}
catch { Assert-Fail "-AsJson" "$_" }
Write-Host ""

# =============================================================================
# SECTION 5: CREATE TABLE + CRUD
# =============================================================================

Write-Host "--- 5. CREATE TABLE + CRUD ---`n" -ForegroundColor Cyan

try {
    Invoke-ThinkSQL "IF OBJECT_ID('ModuleTestTable', 'U') IS NOT NULL DROP TABLE ModuleTestTable"
    Invoke-ThinkSQL "CREATE TABLE ModuleTestTable (Name VARCHAR(100), Age INT)"
    Assert-Pass "CREATE TABLE (auto PK injection)"
}
catch { Assert-Fail "CREATE TABLE" "$_" }

try {
    Invoke-ThinkSQL "INSERT INTO ModuleTestTable (Name, Age) VALUES ('Alice', 30)"
    Invoke-ThinkSQL "INSERT INTO ModuleTestTable (Name, Age) VALUES ('Bob', 25)"
    Invoke-ThinkSQL "INSERT INTO ModuleTestTable (Name, Age) VALUES ('Charlie', 35)"
    Assert-Pass "INSERT 3 rows"
}
catch { Assert-Fail "INSERT" "$_" }

try {
    $rows = Invoke-ThinkSQL "SELECT ID, Name, Age FROM ModuleTestTable ORDER BY Name"
    if ($rows.Count -eq 3 -and $rows[0].Name -eq "Alice") {
        Assert-Pass "SELECT returns 3 rows with auto-generated ID"
    } else {
        Assert-Fail "SELECT after INSERT" "unexpected: $($rows.Count) rows"
    }
}
catch { Assert-Fail "SELECT after INSERT" "$_" }

try {
    Invoke-ThinkSQL "UPDATE ModuleTestTable SET Age = 31 WHERE Name = 'Alice'"
    $alice = Invoke-ThinkSQL "SELECT Age FROM ModuleTestTable WHERE Name = 'Alice'"
    if ($alice.Age -eq 31) {
        Assert-Pass "UPDATE verified"
    } else {
        Assert-Fail "UPDATE" "age=$($alice.Age), expected 31"
    }
}
catch { Assert-Fail "UPDATE" "$_" }

try {
    Invoke-ThinkSQL "DELETE FROM ModuleTestTable WHERE Name = 'Bob'"
    $remaining = Invoke-ThinkSQL "SELECT * FROM ModuleTestTable"
    if ($remaining.Count -eq 2) {
        Assert-Pass "DELETE verified (2 rows remain)"
    } else {
        Assert-Fail "DELETE" "$($remaining.Count) rows remain, expected 2"
    }
}
catch { Assert-Fail "DELETE" "$_" }

try {
    Invoke-ThinkSQL "DROP TABLE ModuleTestTable"
    Assert-Pass "DROP TABLE cleanup"
}
catch { Assert-Fail "DROP TABLE" "$_" }
Write-Host ""

# =============================================================================
# SECTION 6: WITH (CTE)
# =============================================================================

Write-Host "--- 6. WITH (CTE) ---`n" -ForegroundColor Cyan

try {
    $cte = Invoke-ThinkSQL "WITH cte AS (SELECT 1 AS Value) SELECT * FROM cte"
    if ($cte.Value -eq 1) { Assert-Pass "Simple CTE" } else { Assert-Fail "Simple CTE" "unexpected" }
}
catch { Assert-Fail "Simple CTE" "$_" }

try {
    $cte = Invoke-ThinkSQL "WITH a AS (SELECT 1 AS X), b AS (SELECT 2 AS Y) SELECT a.X, b.Y FROM a CROSS JOIN b"
    if ($cte.X -eq 1 -and $cte.Y -eq 2) { Assert-Pass "Multiple CTEs" } else { Assert-Fail "Multiple CTEs" "unexpected" }
}
catch { Assert-Fail "Multiple CTEs" "$_" }

try {
    $cte = Invoke-ThinkSQL "WITH obj AS (SELECT TOP 5 name, type_desc FROM sys.objects) SELECT name, type_desc FROM obj"
    if ($cte.Count -eq 5) { Assert-Pass "CTE with sys.objects (5 rows)" } else { Assert-Fail "CTE sys.objects" "$($cte.Count) rows" }
}
catch { Assert-Fail "CTE sys.objects" "$_" }
Write-Host ""

# =============================================================================
# SECTION 7: DECLARE
# =============================================================================

Write-Host "--- 7. DECLARE ---`n" -ForegroundColor Cyan

try {
    $r = Invoke-ThinkSQL "DECLARE @x INT = 42; SELECT @x AS Answer"
    if ($r.Answer -eq 42) { Assert-Pass "DECLARE + SELECT" } else { Assert-Fail "DECLARE + SELECT" "answer=$($r.Answer)" }
}
catch { Assert-Fail "DECLARE + SELECT" "$_" }

try {
    $r = Invoke-ThinkSQL "DECLARE @a INT = 10, @b INT = 20; SELECT @a + @b AS Sum"
    if ($r.Sum -eq 30) { Assert-Pass "DECLARE multi-var + SELECT" } else { Assert-Fail "DECLARE multi-var" "sum=$($r.Sum)" }
}
catch { Assert-Fail "DECLARE multi-var" "$_" }

try {
    $r = Invoke-ThinkSQL "DECLARE @val INT; SET @val = 99; SELECT @val AS Result"
    if ($r.Result -eq 99) { Assert-Pass "DECLARE + SET + SELECT" } else { Assert-Fail "DECLARE + SET" "result=$($r.Result)" }
}
catch { Assert-Fail "DECLARE + SET" "$_" }

try {
    Invoke-ThinkSQL "DECLARE @x INT = 1; SET @x = @x + 1;"
    Assert-Pass "DECLARE without SELECT (no error)"
}
catch { Assert-Fail "DECLARE without SELECT" "$_" }

try {
    $r = Invoke-ThinkSQL "DECLARE @t TABLE (Id INT, Name VARCHAR(50)); INSERT INTO @t VALUES (1,'Alice'),(2,'Bob'); SELECT * FROM @t"
    if ($r.Count -eq 2) { Assert-Pass "DECLARE table variable + SELECT" } else { Assert-Fail "DECLARE table var" "$($r.Count) rows" }
}
catch { Assert-Fail "DECLARE table var" "$_" }
Write-Host ""

# =============================================================================
# SECTION 8: Pipeline Integration
# =============================================================================

Write-Host "--- 8. Pipeline Integration ---`n" -ForegroundColor Cyan

try {
    $data = Invoke-ThinkSQL "SELECT 10 AS Val UNION ALL SELECT 20 UNION ALL SELECT 30"
    $sum = ($data | Measure-Object -Property Val -Sum).Sum
    if ($sum -eq 60) { Assert-Pass "Measure-Object pipeline (sum=60)" } else { Assert-Fail "Pipeline sum" "got $sum" }
}
catch { Assert-Fail "Pipeline" "$_" }

try {
    $data = Invoke-ThinkSQL "SELECT 'A' AS Letter UNION ALL SELECT 'B' UNION ALL SELECT 'C'"
    $sorted = ($data | Sort-Object Letter -Descending | Select-Object -First 1).Letter
    if ($sorted -eq "C") { Assert-Pass "Sort-Object pipeline" } else { Assert-Fail "Sort pipeline" "got $sorted" }
}
catch { Assert-Fail "Sort pipeline" "$_" }
Write-Host ""

# =============================================================================
# Disconnect & Summary
# =============================================================================

Close-ThinkSQLConnection
Write-Host "Disconnected.`n" -ForegroundColor Yellow

$total = $script:passed + $script:failed
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Results: $($script:passed)/$total passed, $($script:failed) failed" -ForegroundColor $(if ($script:failed -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan

if ($script:failed -gt 0) { exit 1 }
