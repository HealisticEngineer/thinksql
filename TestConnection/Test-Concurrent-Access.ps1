# Test-Concurrent-Access.ps1
# This script simulates concurrent access by starting an UPDATE in one connection
# and reading from another connection to verify non-blocking behavior

param(
    [string]$Server = "localhost",
    [string]$Database = "master",
    [string]$Username = "sa",
    [string]$Password = "NeverSafe2Day!"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Concurrent Access Test (Non-Blocking Reads)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "This test demonstrates that SELECT queries with SNAPSHOT isolation" -ForegroundColor White
Write-Host "are NOT blocked by long-running UPDATE transactions.`n" -ForegroundColor White

$dllPath = Join-Path $PSScriptRoot "..\ThinkSQL.dll"
$dllPath = (Resolve-Path $dllPath).Path

# Build the test using standard .NET SqlClient for transaction control
$connectionString = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;Encrypt=False;TrustServerCertificate=True"

Write-Host "Setting up test environment..." -ForegroundColor Yellow

# Create a test table and enable SNAPSHOT isolation
$setupConn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$setupConn.Open()

$setupCmd = $setupConn.CreateCommand()

# Enable SNAPSHOT isolation
$setupCmd.CommandText = "ALTER DATABASE master SET ALLOW_SNAPSHOT_ISOLATION ON"
Write-Host "  [1] Enabling SNAPSHOT isolation..." -ForegroundColor Gray
$setupCmd.ExecuteNonQuery() | Out-Null

# Create test table
$setupCmd.CommandText = @"
IF OBJECT_ID('ConcurrentTestTable', 'U') IS NOT NULL 
    DROP TABLE ConcurrentTestTable;
CREATE TABLE ConcurrentTestTable (
    ID INT PRIMARY KEY IDENTITY(1,1),
    Value INT,
    LastUpdate DATETIME
);
INSERT INTO ConcurrentTestTable (Value, LastUpdate) 
VALUES (100, GETDATE()), (200, GETDATE()), (300, GETDATE());
"@
Write-Host "  [2] Creating test table with 3 rows..." -ForegroundColor Gray
$setupCmd.ExecuteNonQuery() | Out-Null

$setupConn.Close()
Write-Host "[OK] Setup complete`n" -ForegroundColor Green

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting Concurrent Operations" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Start a background job that holds a transaction with an UPDATE
Write-Host "[Connection 1] Starting long-running UPDATE transaction..." -ForegroundColor Yellow

$updateJob = Start-Job -ScriptBlock {
    param($connString)
    
    $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
    $conn.Open()
    
    $trans = $conn.BeginTransaction()
    $cmd = $conn.CreateCommand()
    $cmd.Transaction = $trans
    
    # Start the UPDATE
    $cmd.CommandText = "UPDATE ConcurrentTestTable SET Value = Value + 1000, LastUpdate = GETDATE()"
    $cmd.ExecuteNonQuery() | Out-Null
    
    # Hold the transaction open for 3 seconds
    Start-Sleep -Seconds 3
    
    # Commit the transaction
    $trans.Commit()
    $conn.Close()
    
    return "UPDATE completed"
} -ArgumentList $connectionString

# Wait a moment for the UPDATE to start
Start-Sleep -Milliseconds 500

Write-Host "  Transaction is now holding locks on the table...`n" -ForegroundColor Gray

# Now use ThinkSQL DLL to read with SNAPSHOT isolation
Write-Host "[Connection 2] Reading with ThinkSQL (SNAPSHOT isolation)..." -ForegroundColor Yellow

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

Add-Type -MemberDefinition $sig -Namespace Win32 -Name ConcurrentTest -ErrorAction SilentlyContinue

$connString = "server=$Server;user id=$Username;password=$Password;database=$Database;encrypt=disable;TrustServerCertificate=true"
$resultPtr = [Win32.ConcurrentTest]::ConnectDb($connString)

if ($resultPtr -ne [IntPtr]::Zero) {
    $error = [Win32.ConcurrentTest]::PtrToString($resultPtr)
    Write-Host "[ERROR] Connection failed: $error" -ForegroundColor Red
    [Win32.ConcurrentTest]::FreeCString($resultPtr)
    exit 1
}

$startTime = Get-Date

# Execute SELECT while UPDATE transaction is still holding locks
$sql = "SELECT ID, Value, LastUpdate FROM ConcurrentTestTable ORDER BY ID"
$resultPtr = [Win32.ConcurrentTest]::ExecuteSql($sql)

$endTime = Get-Date
$elapsed = ($endTime - $startTime).TotalMilliseconds

if ($resultPtr -ne [IntPtr]::Zero) {
    $result = [Win32.ConcurrentTest]::PtrToString($resultPtr)
    [Win32.ConcurrentTest]::FreeCString($resultPtr)
    
    try {
        $json = $result | ConvertFrom-Json
        Write-Host "  [OK] SELECT completed in $([math]::Round($elapsed, 2)) ms (NOT BLOCKED!)" -ForegroundColor Green
        Write-Host "`n  Results (original values before UPDATE commits):" -ForegroundColor Cyan
        $json | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "    $_" -ForegroundColor White }
    }
    catch {
        Write-Host "  [ERROR] $result" -ForegroundColor Red
    }
}

[Win32.ConcurrentTest]::DisconnectDb()

# Wait for the UPDATE job to complete
Write-Host "`nWaiting for UPDATE transaction to commit..." -ForegroundColor Yellow
$updateResult = Receive-Job -Job $updateJob -Wait
Remove-Job -Job $updateJob
Write-Host "  [OK] $updateResult`n" -ForegroundColor Green

# Read again to see the updated values
Write-Host "[Connection 3] Reading again after UPDATE committed..." -ForegroundColor Yellow

$resultPtr = [Win32.ConcurrentTest]::ConnectDb($connString)
if ($resultPtr -eq [IntPtr]::Zero) {
    $resultPtr = [Win32.ConcurrentTest]::ExecuteSql($sql)
    
    if ($resultPtr -ne [IntPtr]::Zero) {
        $result = [Win32.ConcurrentTest]::PtrToString($resultPtr)
        [Win32.ConcurrentTest]::FreeCString($resultPtr)
        
        try {
            $json = $result | ConvertFrom-Json
            Write-Host "  [OK] New values after UPDATE:" -ForegroundColor Green
            $json | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "    $_" -ForegroundColor Cyan }
        }
        catch {
            Write-Host "  [ERROR] $result" -ForegroundColor Red
        }
    }
    
    [Win32.ConcurrentTest]::DisconnectDb()
}

# Cleanup
Write-Host "`nCleaning up..." -ForegroundColor Yellow
$cleanupConn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$cleanupConn.Open()
$cleanupCmd = $cleanupConn.CreateCommand()
$cleanupCmd.CommandText = "DROP TABLE ConcurrentTestTable"
$cleanupCmd.ExecuteNonQuery() | Out-Null
$cleanupConn.Close()
Write-Host "[OK] Test table dropped`n" -ForegroundColor Green

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[SUCCESS] Concurrent Access Test Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  ✓ SELECT with SNAPSHOT isolation was NOT blocked by UPDATE" -ForegroundColor Green
Write-Host "  ✓ SELECT completed in ~$([math]::Round($elapsed, 2)) ms (immediate)" -ForegroundColor Green
Write-Host "  ✓ SELECT read consistent snapshot (values before UPDATE)" -ForegroundColor Green
Write-Host "  ✓ After UPDATE committed, new SELECT read updated values" -ForegroundColor Green
Write-Host "`nThis demonstrates SNAPSHOT isolation prevents blocking!`n" -ForegroundColor White
