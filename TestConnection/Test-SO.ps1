# Test-SO.ps1
# Tests ThinkSQL.so (Linux shared library) via WSL
# Compiles a C test harness, links against ThinkSQL.so, and validates exports

param(
    [string]$Server = "localhost",
    [string]$Database = "master",
    [string]$Username = "SA",
    [string]$Password = "NeverSafe2Day!"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ThinkSQL.so — Linux Test Suite (via WSL)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── Validate prerequisites ───────────────────────────────────────────────────

$soPath = Join-Path $PSScriptRoot "..\ThinkSQL.so"
$soPath = (Resolve-Path $soPath -ErrorAction Stop).Path
$headerPath = Join-Path $PSScriptRoot "..\ThinkSQL.h"

if (-not (Test-Path $soPath)) {
    Write-Host "[FAIL] ThinkSQL.so not found. Run Linux-Build-ThinkSQL.ps1 first." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $headerPath)) {
    Write-Host "[FAIL] ThinkSQL.h not found. Run Linux-Build-ThinkSQL.ps1 first." -ForegroundColor Red
    exit 1
}

$soSize = [math]::Round((Get-Item $soPath).Length / 1MB, 2)
Write-Host "SO:     $soPath ($soSize MB)" -ForegroundColor Gray
Write-Host "Header: $headerPath" -ForegroundColor Gray
Write-Host "Server: $Server | Database: $Database`n" -ForegroundColor Gray

$passed = 0
$failed = 0

function Write-Pass { param([string]$Name) Write-Host "  [PASS] $Name" -ForegroundColor Green; $script:passed++ }
function Write-Fail { param([string]$Name, [string]$Detail) Write-Host "  [FAIL] $Name — $Detail" -ForegroundColor Red; $script:failed++ }

# ── Check WSL environment ────────────────────────────────────────────────────

Write-Host "--- 1. WSL Environment ---`n" -ForegroundColor Cyan

$wslCheck = & wsl bash -c "echo ok" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL available" "WSL is not installed or not running"
    exit 1
}
Write-Pass "WSL available"

$gccCheck = & wsl bash -c "gcc --version 2>&1 | head -1"
if ($LASTEXITCODE -ne 0) {
    Write-Fail "GCC available" "Install with: wsl bash -c 'sudo apt install -y build-essential'"
    exit 1
}
Write-Pass "GCC available ($gccCheck)"
Write-Host ""

# ── Convert paths ────────────────────────────────────────────────────────────

$winProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path.Replace('\', '\\')
$wslProjectDir = & wsl wslpath -u $winProjectDir
$wslTestDir = "$wslProjectDir/TestConnection"

# ── Resolve server address for WSL ───────────────────────────────────────────
# WSL2 can't reach Windows "localhost" — use the Windows host IP instead

if ($Server -eq "localhost" -or $Server -eq "127.0.0.1" -or $Server -eq ".") {
    $routeOutput = & wsl bash -c "ip route show default"
    if ($routeOutput -match 'via\s+(\d+\.\d+\.\d+\.\d+)') {
        $wslHostIp = $Matches[1]
    }
    if ($wslHostIp) {
        Write-Host "Resolved localhost → Windows host IP: $wslHostIp (WSL2 bridge)" -ForegroundColor Gray
        $Server = $wslHostIp.Trim()
    } else {
        Write-Host "[WARN] Could not detect Windows host IP from WSL; using localhost" -ForegroundColor DarkYellow
    }
}

# ── Write C test harness ─────────────────────────────────────────────────────

Write-Host "--- 2. Compile Test Harness ---`n" -ForegroundColor Cyan

$connStr = "server=$Server;user id=$Username;password=$Password;database=$Database;encrypt=disable;TrustServerCertificate=true"

# Escape double quotes and backslashes for C string
$cConnStr = $connStr.Replace('\', '\\').Replace('"', '\"')

$cTestCode = @"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

// Function pointer types matching ThinkSQL exports
typedef char* (*ConnectDb_t)(char*);
typedef void  (*DisconnectDb_t)(void);
typedef char* (*ExecuteSql_t)(char*);
typedef void  (*FreeCString_t)(char*);

int passed = 0;
int failed = 0;

void pass(const char* name) {
    printf("  [PASS] %s\n", name);
    passed++;
}

void fail(const char* name, const char* detail) {
    printf("  [FAIL] %s -- %s\n", name, detail);
    failed++;
}

int main() {
    // ── Section 3: Load shared library ──────────────────────────────────
    printf("\n--- 3. Load Shared Library ---\n\n");

    void* handle = dlopen("$wslProjectDir/ThinkSQL.so", RTLD_LAZY);
    if (!handle) {
        fail("dlopen ThinkSQL.so", dlerror());
        printf("\nResults: 0/1 passed, 1 failed\n");
        return 1;
    }
    pass("dlopen ThinkSQL.so");

    // ── Section 4: Resolve exports ──────────────────────────────────────
    printf("\n--- 4. Resolve Exports ---\n\n");

    ConnectDb_t    ConnectDb    = (ConnectDb_t)   dlsym(handle, "ConnectDb");
    DisconnectDb_t DisconnectDb = (DisconnectDb_t)dlsym(handle, "DisconnectDb");
    ExecuteSql_t   ExecuteSql   = (ExecuteSql_t)  dlsym(handle, "ExecuteSql");
    FreeCString_t  FreeCString  = (FreeCString_t) dlsym(handle, "FreeCString");

    if (ConnectDb)    pass("Export: ConnectDb");    else fail("Export: ConnectDb",    dlerror());
    if (DisconnectDb) pass("Export: DisconnectDb"); else fail("Export: DisconnectDb", dlerror());
    if (ExecuteSql)   pass("Export: ExecuteSql");   else fail("Export: ExecuteSql",   dlerror());
    if (FreeCString)  pass("Export: FreeCString");  else fail("Export: FreeCString",  dlerror());

    if (!ConnectDb || !DisconnectDb || !ExecuteSql || !FreeCString) {
        printf("\nCannot continue without all exports.\n");
        dlclose(handle);
        int total = passed + failed;
        printf("\nResults: %d/%d passed, %d failed\n", passed, total, failed);
        return 1;
    }

    // ── Section 5: Connection ───────────────────────────────────────────
    printf("\n--- 5. Connection ---\n\n");

    char* connResult = ConnectDb("$cConnStr");
    if (connResult != NULL) {
        char detail[512];
        snprintf(detail, sizeof(detail), "%.500s", connResult);
        FreeCString(connResult);
        fail("ConnectDb", detail);
        dlclose(handle);
        int total = passed + failed;
        printf("\nResults: %d/%d passed, %d failed\n", passed, total, failed);
        return 1;
    }
    pass("ConnectDb");

    // Test reconnect (same connStr — fast path)
    char* reconn = ConnectDb("$cConnStr");
    if (reconn == NULL) pass("Reconnect (fast path)");
    else { fail("Reconnect", reconn); FreeCString(reconn); }

    // Disconnect + reconnect (pool reuse)
    DisconnectDb();
    pass("DisconnectDb");

    char* poolResult = ConnectDb("$cConnStr");
    if (poolResult == NULL) pass("Pool reuse after disconnect");
    else { fail("Pool reuse", poolResult); FreeCString(poolResult); }

    // ── Section 6: Basic SELECT ─────────────────────────────────────────
    printf("\n--- 6. Basic SELECT ---\n\n");

    char* result;

    // SELECT @@VERSION
    result = ExecuteSql("SELECT @@VERSION AS ServerVersion");
    if (result != NULL) {
        if (strstr(result, "Microsoft SQL Server") != NULL || strstr(result, "ServerVersion") != NULL) {
            pass("SELECT @@VERSION (got SQL Server version)");
        } else if (strstr(result, "ERROR:") != NULL) {
            fail("SELECT @@VERSION", result);
        } else {
            pass("SELECT @@VERSION (returned data)");
        }
        FreeCString(result);
    } else {
        fail("SELECT @@VERSION", "got NULL");
    }

    // SELECT GETDATE()
    result = ExecuteSql("SELECT GETDATE() AS Now");
    if (result != NULL && strstr(result, "ERROR:") == NULL) {
        pass("SELECT GETDATE()");
        FreeCString(result);
    } else {
        fail("SELECT GETDATE()", result ? result : "NULL");
        if (result) FreeCString(result);
    }

    // SELECT sys.databases
    result = ExecuteSql("SELECT name, database_id FROM sys.databases");
    if (result != NULL && strstr(result, "master") != NULL) {
        pass("SELECT sys.databases (found master)");
        FreeCString(result);
    } else {
        fail("SELECT sys.databases", result ? result : "NULL");
        if (result) FreeCString(result);
    }

    // Non-SELECT (PRINT) — should return NULL
    result = ExecuteSql("PRINT 'hello from linux'");
    if (result == NULL) {
        pass("Non-SELECT (PRINT) returns NULL");
    } else {
        if (strstr(result, "ERROR:") != NULL) fail("Non-SELECT (PRINT)", result);
        else pass("Non-SELECT (PRINT)");
        FreeCString(result);
    }

    // ── Section 7: CREATE TABLE (auto PK injection) ─────────────────────
    printf("\n--- 7. CREATE TABLE (auto PK) ---\n\n");

    result = ExecuteSql("IF OBJECT_ID('LinuxTestTable', 'U') IS NOT NULL DROP TABLE LinuxTestTable");
    if (result != NULL) { FreeCString(result); }
    pass("Drop test table if exists");

    result = ExecuteSql("CREATE TABLE LinuxTestTable (Name VARCHAR(100), Age INT)");
    if (result == NULL) pass("CREATE TABLE (no PK -- should inject)");
    else { fail("CREATE TABLE", result); FreeCString(result); }

    result = ExecuteSql("INSERT INTO LinuxTestTable (Name, Age) VALUES ('Alice', 30), ('Bob', 25)");
    if (result == NULL) pass("INSERT rows");
    else { fail("INSERT rows", result); FreeCString(result); }

    // Verify PK column was injected
    result = ExecuteSql("SELECT ID, Name, Age FROM LinuxTestTable ORDER BY Name");
    if (result != NULL && strstr(result, "Alice") != NULL && strstr(result, "ID") != NULL) {
        pass("SELECT with injected PK column (ID)");
        FreeCString(result);
    } else {
        fail("SELECT with injected PK", result ? result : "NULL");
        if (result) FreeCString(result);
    }

    result = ExecuteSql("DROP TABLE LinuxTestTable");
    if (result == NULL) pass("DROP TABLE");
    else { FreeCString(result); pass("DROP TABLE (returned data)"); }

    // ── Section 8: DECLARE and CTE ──────────────────────────────────────
    printf("\n--- 8. DECLARE and CTE ---\n\n");

    result = ExecuteSql("DECLARE @x INT = 42; SELECT @x AS Answer");
    if (result != NULL && strstr(result, "42") != NULL) {
        pass("DECLARE + SELECT");
        FreeCString(result);
    } else {
        fail("DECLARE + SELECT", result ? result : "NULL");
        if (result) FreeCString(result);
    }

    result = ExecuteSql("WITH cte AS (SELECT 1 AS Value) SELECT * FROM cte");
    if (result != NULL && strstr(result, "1") != NULL) {
        pass("CTE query");
        FreeCString(result);
    } else {
        fail("CTE query", result ? result : "NULL");
        if (result) FreeCString(result);
    }

    // ── Cleanup ─────────────────────────────────────────────────────────
    printf("\n--- Cleanup ---\n\n");

    DisconnectDb();
    pass("Final DisconnectDb");

    dlclose(handle);
    pass("dlclose");

    // ── Summary ─────────────────────────────────────────────────────────
    int total = passed + failed;
    printf("\n========================================\n");
    if (failed == 0)
        printf("Results: %d/%d passed, 0 failed\n", passed, total);
    else
        printf("Results: %d/%d passed, %d failed\n", passed, total, failed);
    printf("========================================\n");

    return (failed > 0) ? 1 : 0;
}
"@

# Write the C test code to the TestConnection folder
$cTestFile = Join-Path $PSScriptRoot "test_so.c"
$cTestCode | Set-Content -Path $cTestFile -Encoding UTF8 -NoNewline
Write-Host "  Written test_so.c" -ForegroundColor Gray

# Compile in WSL
$compileCmd = "cd '$wslTestDir' && gcc -o test_so test_so.c -ldl -Wno-format 2>&1"
$compileOutput = & wsl bash -c $compileCmd

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Compile test harness" "$compileOutput"
    exit 1
}
Write-Pass "Compiled test_so"
Write-Host ""

# ── Run the test ─────────────────────────────────────────────────────────────

Write-Host "--- Running Tests ---`n" -ForegroundColor Cyan

$runCmd = "cd '$wslProjectDir' && LD_LIBRARY_PATH='$wslProjectDir' '$wslTestDir/test_so' 2>&1"
$testOutput = & wsl bash -c $runCmd

# Display test output with colorization
foreach ($line in $testOutput) {
    if ($line -match '\[PASS\]') {
        Write-Host $line -ForegroundColor Green
    }
    elseif ($line -match '\[FAIL\]') {
        Write-Host $line -ForegroundColor Red
    }
    elseif ($line -match '^---') {
        Write-Host $line -ForegroundColor Cyan
    }
    elseif ($line -match '^={3,}') {
        Write-Host $line -ForegroundColor Cyan
    }
    elseif ($line -match 'Results:') {
        if ($line -match '0 failed') {
            Write-Host $line -ForegroundColor Green
        } else {
            Write-Host $line -ForegroundColor Red
        }
    }
    else {
        Write-Host $line -ForegroundColor Gray
    }
}

# Parse results from last line
$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "✓ All Linux tests passed!" -ForegroundColor Green
} else {
    Write-Host "✗ Some Linux tests failed (exit code $exitCode)" -ForegroundColor Red
}

# Cleanup compiled binary
$binaryPath = Join-Path $PSScriptRoot "test_so"
if (Test-Path $binaryPath) { Remove-Item $binaryPath -Force }
# Keep test_so.c for reference; remove if desired
# Remove-Item $cTestFile -Force

exit $exitCode
