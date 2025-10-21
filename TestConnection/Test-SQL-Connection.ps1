# Test-SQL-Connection.ps1
# This script tests the ConnectDb function from ThinkSQL.dll with a real SQL Server connection

param(
    [Parameter(Mandatory=$false)]
    [string]$Server = "localhost",
    
    [Parameter(Mandatory=$false)]
    [string]$Database = "master",
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "sa",
    
    [Parameter(Mandatory=$false)]
    [string]$Password = ""
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing SQL Server Connection via ThinkSQL.dll" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get the DLL path
$dllPath = Join-Path $PSScriptRoot "..\ThinkSQL.dll"
$dllPath = (Resolve-Path $dllPath -ErrorAction Stop).Path

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  DLL Path: $dllPath" -ForegroundColor Gray
Write-Host "  Server: $Server" -ForegroundColor Gray
Write-Host "  Database: $Database" -ForegroundColor Gray
Write-Host "  Username: $Username" -ForegroundColor Gray
Write-Host "  Password: $(if($Password) {'*****'} else {'(empty)'})" -ForegroundColor Gray
Write-Host ""

# Check if password is provided
if ([string]::IsNullOrEmpty($Password)) {
    $Password = Read-Host "Enter SQL Server password for user '$Username'" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

# Define the C# P/Invoke signatures
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
    Write-Host "Loading DLL..." -ForegroundColor Yellow
    Add-Type -MemberDefinition $sig -Namespace Win32 -Name ThinkSQL -ErrorAction Stop
    Write-Host "[OK] DLL loaded successfully" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "[FAIL] Failed to load DLL" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

# Build the connection string
$connString = "server=$Server;user id=$Username;password=$Password;database=$Database"
Write-Host "Attempting to connect to SQL Server..." -ForegroundColor Yellow

try {
    # Call ConnectDb
    $resultPtr = [Win32.ThinkSQL]::ConnectDb($connString)
    
    if ($resultPtr -eq [IntPtr]::Zero) {
        # Success - null pointer means no error
        Write-Host "[OK] Successfully connected to SQL Server!" -ForegroundColor Green
        Write-Host ""
        
        # Test a simple SQL query
        Write-Host "Testing SQL execution..." -ForegroundColor Yellow
        $testQuery = "SELECT @@VERSION AS Version"
        
        $execResultPtr = [Win32.ThinkSQL]::ExecuteSql($testQuery)
        
        if ($execResultPtr -eq [IntPtr]::Zero) {
            Write-Host "[OK] SQL query executed successfully!" -ForegroundColor Green
            Write-Host "  Query: $testQuery" -ForegroundColor Gray
        }
        else {
            $error = [Win32.ThinkSQL]::PtrToString($execResultPtr)
            Write-Host "[FAIL] SQL query failed: $error" -ForegroundColor Red
            [Win32.ThinkSQL]::FreeCString($execResultPtr)
        }
        
        Write-Host ""
        Write-Host "Disconnecting..." -ForegroundColor Yellow
        [Win32.ThinkSQL]::DisconnectDb()
        Write-Host "[OK] Disconnected successfully" -ForegroundColor Green
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "[OK] ALL TESTS PASSED" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
    }
    else {
        # Error - pointer contains error message
        $error = [Win32.ThinkSQL]::PtrToString($resultPtr)
        Write-Host "[FAIL] Connection failed: $error" -ForegroundColor Red
        [Win32.ThinkSQL]::FreeCString($resultPtr)
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "[FAIL] TEST FAILED" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Cyan
        
        exit 1
    }
}
catch {
    Write-Host "[ERROR] Exception occurred: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Connection test completed successfully!" -ForegroundColor Cyan
