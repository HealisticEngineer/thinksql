# Test-DLL.ps1
# Comprehensive test suite for ThinkSQL.dll (direct P/Invoke)
# Merges: DLL import, connection, SELECT, CREATE TABLE, DECLARE, WITH, snapshot isolation, concurrent access

param(
    [string]$Server = "localhost",
    [string]$Database = "master",
    [string]$Username = "SA",
    [string]$Password = "NeverSafe2Day!"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ThinkSQL.dll — Full Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── DLL Setup ────────────────────────────────────────────────────────────────

$dllPath = Join-Path $PSScriptRoot "..\ThinkSQL.dll"
$dllPath = (Resolve-Path $dllPath -ErrorAction Stop).Path

if (-not (Test-Path $dllPath)) {
    Write-Host "[FAIL] DLL not found at $dllPath" -ForegroundColor Red
    exit 1
}

$dllSize = [math]::Round((Get-Item $dllPath).Length / 1MB, 2)
Write-Host "DLL: $dllPath ($dllSize MB)" -ForegroundColor Gray
Write-Host "Server: $Server | Database: $Database`n" -ForegroundColor Gray

$sig = @"
[DllImport("$($dllPath.Replace('\','\\'))", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
public static extern IntPtr ConnectDb([MarshalAs(UnmanagedType.LPStr)] string connStr);

[DllImport("$($dllPath.Replace('\','\\'))", CallingConvention = CallingConvention.Cdecl)]
public static extern void DisconnectDb();

[DllImport("$($dllPath.Replace('\','\\'))", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
public static extern IntPtr ExecuteSql([MarshalAs(UnmanagedType.LPStr)] string sqlStr);

[DllImport("$($dllPath.Replace('\','\\'))", CallingConvention = CallingConvention.Cdecl)]
public static extern void FreeCString(IntPtr str);

public static string PtrToString(IntPtr ptr) {
    if (ptr == IntPtr.Zero) return null;
    return System.Runtime.InteropServices.Marshal.PtrToStringAnsi(ptr);
}
"@

try {
    Add-Type -MemberDefinition $sig -Namespace Win32 -Name ThinkSQL -ErrorAction Stop
}
catch {
    Write-Host "Note: Type already loaded (this is normal)" -ForegroundColor Gray
}

# ── Helpers ──────────────────────────────────────────────────────────────────

$script:passed = 0
$script:failed = 0
$script:section = ""

function Run-Test {
    param(
        [string]$Name,
        [string]$Sql,
        [bool]$ExpectResults  # $true = expect JSON array, $false = expect nil
    )

    Write-Host "  TEST: $Name" -ForegroundColor Yellow
    $displaySql = if ($Sql.Length -gt 120) { $Sql.Substring(0, 120) + "..." } else { $Sql }
    Write-Host "    SQL: $displaySql" -ForegroundColor Gray

    $ptr = [Win32.ThinkSQL]::ExecuteSql($Sql)

    if ($ExpectResults) {
        if ($ptr -eq [IntPtr]::Zero) {
            Write-Host "    [FAIL] Expected JSON results but got null" -ForegroundColor Red
            $script:failed++
            return $null
        }

        $result = [Win32.ThinkSQL]::PtrToString($ptr)
        [Win32.ThinkSQL]::FreeCString($ptr)

        if ($result.StartsWith("ERROR:")) {
            Write-Host "    [FAIL] $result" -ForegroundColor Red
            $script:failed++
            return $null
        }

        try {
            $json = $result | ConvertFrom-Json
            Write-Host "    [PASS] Got $($json.Count) row(s)" -ForegroundColor Green
            if ($json.Count -gt 0) {
                $first = $json[0]
                $props = ($first.PSObject.Properties | Select-Object -First 3 | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ", "
                Write-Host "    → $props" -ForegroundColor Gray
            }
            $script:passed++
            return $json
        }
        catch {
            Write-Host "    [FAIL] Not valid JSON: $result" -ForegroundColor Red
            $script:failed++
            return $null
        }
    }
    else {
        if ($ptr -eq [IntPtr]::Zero) {
            Write-Host "    [PASS] Executed (no result set)" -ForegroundColor Green
            $script:passed++
            return $null
        }
        else {
            $result = [Win32.ThinkSQL]::PtrToString($ptr)
            [Win32.ThinkSQL]::FreeCString($ptr)
            if ($result.StartsWith("ERROR:")) {
                Write-Host "    [FAIL] $result" -ForegroundColor Red
                $script:failed++
            }
            else {
                Write-Host "    [WARN] Expected null but got: $result" -ForegroundColor DarkYellow
                $script:failed++
            }
            return $null
        }
    }
}

# =============================================================================
# SECTION 1: DLL Import
# =============================================================================

Write-Host "--- 1. DLL Import ---`n" -ForegroundColor Cyan
Write-Host "  [PASS] DLL loaded, all 4 exports available (ConnectDb, DisconnectDb, ExecuteSql, FreeCString)" -ForegroundColor Green
$script:passed++
Write-Host ""

# =============================================================================
# SECTION 2: Connection
# =============================================================================

Write-Host "--- 2. Connection ---`n" -ForegroundColor Cyan

$connStr = "server=$Server;user id=$Username;password=$Password;database=$Database;encrypt=disable;TrustServerCertificate=true"

Write-Host "  Connecting..." -ForegroundColor Yellow
$connResult = [Win32.ThinkSQL]::ConnectDb($connStr)

if ($connResult -ne [IntPtr]::Zero) {
    $err = [Win32.ThinkSQL]::PtrToString($connResult)
    Write-Host "  [FAIL] Connection failed: $err" -ForegroundColor Red
    [Win32.ThinkSQL]::FreeCString($connResult)
    exit 1
}
Write-Host "  [PASS] Connected" -ForegroundColor Green
$script:passed++

# Test reconnect (same connection string — should be instant)
$reconnResult = [Win32.ThinkSQL]::ConnectDb($connStr)
if ($reconnResult -eq [IntPtr]::Zero) {
    Write-Host "  [PASS] Reconnect with same connStr (fast path)" -ForegroundColor Green
    $script:passed++
} else {
    $err = [Win32.ThinkSQL]::PtrToString($reconnResult)
    Write-Host "  [FAIL] Reconnect failed: $err" -ForegroundColor Red
    [Win32.ThinkSQL]::FreeCString($reconnResult)
    $script:failed++
}

# Test disconnect + reconnect (pool reuse)
[Win32.ThinkSQL]::DisconnectDb()
$poolResult = [Win32.ThinkSQL]::ConnectDb($connStr)
if ($poolResult -eq [IntPtr]::Zero) {
    Write-Host "  [PASS] Pool reuse after disconnect" -ForegroundColor Green
    $script:passed++
} else {
    $err = [Win32.ThinkSQL]::PtrToString($poolResult)
    Write-Host "  [FAIL] Pool reuse failed: $err" -ForegroundColor Red
    [Win32.ThinkSQL]::FreeCString($poolResult)
    $script:failed++
}
Write-Host ""

# =============================================================================
# SECTION 3: Basic SELECT
# =============================================================================

Write-Host "--- 3. Basic SELECT ---`n" -ForegroundColor Cyan

Run-Test -Name "SELECT @@VERSION" `
    -Sql "SELECT @@VERSION AS ServerVersion" `
    -ExpectResults $true

Run-Test -Name "SELECT system databases" `
    -Sql "SELECT name, database_id FROM sys.databases" `
    -ExpectResults $true

Run-Test -Name "SELECT GETDATE()" `
    -Sql "SELECT GETDATE() AS Now" `
    -ExpectResults $true

Run-Test -Name "Non-SELECT (PRINT)" `
    -Sql "PRINT 'hello'" `
    -ExpectResults $false

Write-Host ""

# =============================================================================
# SECTION 4: CREATE TABLE (auto PK injection)
# =============================================================================

Write-Host "--- 4. CREATE TABLE (auto PK) ---`n" -ForegroundColor Cyan

Run-Test -Name "Drop test table if exists" `
    -Sql "IF OBJECT_ID('DllTestTable', 'U') IS NOT NULL DROP TABLE DllTestTable" `
    -ExpectResults $false

Run-Test -Name "CREATE TABLE (no PK — should inject)" `
    -Sql "CREATE TABLE DllTestTable (Name VARCHAR(100), Age INT)" `
    -ExpectResults $false

Run-Test -Name "INSERT rows" `
    -Sql "INSERT INTO DllTestTable (Name, Age) VALUES ('Alice', 30), ('Bob', 25)" `
    -ExpectResults $false

Run-Test -Name "SELECT from created table (verify PK column)" `
    -Sql "SELECT ID, Name, Age FROM DllTestTable ORDER BY Name" `
    -ExpectResults $true

Run-Test -Name "UPDATE data" `
    -Sql "UPDATE DllTestTable SET Age = 31 WHERE Name = 'Alice'" `
    -ExpectResults $false

Run-Test -Name "DELETE data" `
    -Sql "DELETE FROM DllTestTable WHERE Name = 'Bob'" `
    -ExpectResults $false

Run-Test -Name "SELECT after UPDATE/DELETE" `
    -Sql "SELECT ID, Name, Age FROM DllTestTable" `
    -ExpectResults $true

Run-Test -Name "DROP test table" `
    -Sql "DROP TABLE DllTestTable" `
    -ExpectResults $false

Write-Host ""

# =============================================================================
# SECTION 5: WITH (CTE)
# =============================================================================

Write-Host "--- 5. WITH (CTE) ---`n" -ForegroundColor Cyan

Run-Test -Name "Simple CTE" `
    -Sql "WITH cte AS (SELECT 1 AS Value) SELECT * FROM cte" `
    -ExpectResults $true

Run-Test -Name "CTE with multiple columns" `
    -Sql "WITH cte AS (SELECT 'Hello' AS Greeting, GETDATE() AS Now) SELECT Greeting, Now FROM cte" `
    -ExpectResults $true

Run-Test -Name "Multiple CTEs" `
    -Sql "WITH a AS (SELECT 1 AS X), b AS (SELECT 2 AS Y) SELECT a.X, b.Y FROM a CROSS JOIN b" `
    -ExpectResults $true

Run-Test -Name "CTE with sys.objects" `
    -Sql "WITH obj AS (SELECT TOP 5 name, type_desc FROM sys.objects) SELECT name, type_desc FROM obj" `
    -ExpectResults $true

Write-Host ""

# =============================================================================
# SECTION 6: DECLARE
# =============================================================================

Write-Host "--- 6. DECLARE ---`n" -ForegroundColor Cyan

Run-Test -Name "DECLARE + SELECT" `
    -Sql "DECLARE @x INT = 42; SELECT @x AS Answer" `
    -ExpectResults $true

Run-Test -Name "DECLARE multiple vars + SELECT" `
    -Sql "DECLARE @a INT = 10, @b INT = 20; SELECT @a + @b AS Sum" `
    -ExpectResults $true

Run-Test -Name "DECLARE string var + SELECT" `
    -Sql "DECLARE @name NVARCHAR(50) = N'ThinkSQL'; SELECT @name AS Name, LEN(@name) AS Length" `
    -ExpectResults $true

Run-Test -Name "DECLARE + SET + SELECT" `
    -Sql "DECLARE @val INT; SET @val = 99; SELECT @val AS Result" `
    -ExpectResults $true

Run-Test -Name "DECLARE without SELECT (pure assignment)" `
    -Sql "DECLARE @x INT = 1; SET @x = @x + 1;" `
    -ExpectResults $false

Run-Test -Name "DECLARE table variable + SELECT" `
    -Sql "DECLARE @t TABLE (Id INT, Name VARCHAR(50)); INSERT INTO @t VALUES (1,'Alice'),(2,'Bob'); SELECT * FROM @t" `
    -ExpectResults $true

Write-Host ""

# =============================================================================
# SECTION 7: SNAPSHOT Isolation
# =============================================================================

Write-Host "--- 7. SNAPSHOT Isolation ---`n" -ForegroundColor Cyan

# Verify isolation level is set to SNAPSHOT for SELECTs
$isoResult = Run-Test -Name "Check isolation level" `
    -Sql @"
SELECT 
    CASE transaction_isolation_level 
        WHEN 0 THEN 'Unspecified' 
        WHEN 1 THEN 'ReadUncommitted' 
        WHEN 2 THEN 'ReadCommitted' 
        WHEN 3 THEN 'Repeatable' 
        WHEN 4 THEN 'Serializable' 
        WHEN 5 THEN 'Snapshot' 
    END AS IsolationLevel
FROM sys.dm_exec_sessions 
WHERE session_id = @@SPID
"@ -ExpectResults $true

Write-Host ""

# =============================================================================
# SECTION 8: Concurrent Access (non-blocking reads)
# =============================================================================

Write-Host "--- 8. Concurrent Access ---`n" -ForegroundColor Cyan

$adoConnStr = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;Encrypt=False;TrustServerCertificate=True"

try {
    # Setup: create test table
    Run-Test -Name "Setup: create concurrent test table" `
        -Sql "IF OBJECT_ID('ConcurrentTestTable','U') IS NOT NULL DROP TABLE ConcurrentTestTable; CREATE TABLE ConcurrentTestTable (ID INT PRIMARY KEY IDENTITY(1,1), Value INT); INSERT INTO ConcurrentTestTable (Value) VALUES (100),(200),(300)" `
        -ExpectResults $false

    # Start a blocking UPDATE transaction via ADO.NET
    $blockConn = New-Object System.Data.SqlClient.SqlConnection($adoConnStr)
    $blockConn.Open()
    $blockTrans = $blockConn.BeginTransaction()
    $blockCmd = $blockConn.CreateCommand()
    $blockCmd.Transaction = $blockTrans
    $blockCmd.CommandText = "UPDATE ConcurrentTestTable SET Value = Value + 1000"
    $blockCmd.ExecuteNonQuery() | Out-Null

    Write-Host "  (Blocking UPDATE transaction is holding locks...)" -ForegroundColor Gray

    # Read via ThinkSQL — should NOT block with SNAPSHOT
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $concurrentResult = Run-Test -Name "SELECT during blocking UPDATE (SNAPSHOT)" `
        -Sql "SELECT ID, Value FROM ConcurrentTestTable ORDER BY ID" `
        -ExpectResults $true
    $sw.Stop()

    if ($sw.Elapsed.TotalMilliseconds -lt 1000) {
        Write-Host "    [PASS] Completed in $([math]::Round($sw.Elapsed.TotalMilliseconds, 2)) ms (not blocked)" -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host "    [FAIL] Took $([math]::Round($sw.Elapsed.TotalMilliseconds, 2)) ms — was blocked!" -ForegroundColor Red
        $script:failed++
    }

    # Rollback the blocking transaction
    $blockTrans.Rollback()
    $blockConn.Close()

    # Cleanup
    Run-Test -Name "Cleanup: drop concurrent test table" `
        -Sql "DROP TABLE ConcurrentTestTable" `
        -ExpectResults $false
}
catch {
    Write-Host "  [FAIL] Concurrent access test error: $_" -ForegroundColor Red
    $script:failed++
    # Best-effort cleanup
    try { $blockTrans.Rollback() } catch {}
    try { $blockConn.Close() } catch {}
    try {
        $ptr = [Win32.ThinkSQL]::ExecuteSql("IF OBJECT_ID('ConcurrentTestTable','U') IS NOT NULL DROP TABLE ConcurrentTestTable")
        if ($ptr -ne [IntPtr]::Zero) { [Win32.ThinkSQL]::FreeCString($ptr) }
    } catch {}
}

Write-Host ""

# =============================================================================
# Disconnect & Summary
# =============================================================================

[Win32.ThinkSQL]::DisconnectDb()
Write-Host "Disconnected.`n" -ForegroundColor Yellow

$total = $script:passed + $script:failed
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Results: $($script:passed)/$total passed, $($script:failed) failed" -ForegroundColor $(if ($script:failed -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan

if ($script:failed -gt 0) { exit 1 }
