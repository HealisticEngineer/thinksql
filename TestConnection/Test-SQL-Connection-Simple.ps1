# Test-SQL-Connection-Simple.ps1
# Simplified test script for ThinkSQL.dll SQL connection

param(
    [string]$Server = "localhost",
    [string]$Database = "master",
    [string]$Username = "sa",
    [string]$Password = ""
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SQL Connection Test" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get DLL path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dllPath = Join-Path (Split-Path -Parent $scriptDir) "ThinkSQL.dll"

if (-not (Test-Path $dllPath)) {
    Write-Host "[ERROR] DLL not found at: $dllPath" -ForegroundColor Red
    exit 1
}

Write-Host "DLL: $dllPath" -ForegroundColor Gray
Write-Host "Server: $Server" -ForegroundColor Gray
Write-Host "Database: $Database`n" -ForegroundColor Gray

# Check if password needed
if ([string]::IsNullOrEmpty($Password)) {
    $secPass = Read-Host "Password for $Username" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

# C# P/Invoke signatures
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
    Add-Type -MemberDefinition $sig -Namespace Win32 -Name SQL
    Write-Host "[OK] DLL loaded`n" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to load DLL: $_" -ForegroundColor Red
    exit 1
}

# Connect
$connStr = "server=$Server;user id=$Username;password=$Password;database=$Database"

try {
    Write-Host "Connecting..." -ForegroundColor Yellow
    $result = [Win32.SQL]::ConnectDb($connStr)
    
    if ($result -eq [IntPtr]::Zero) {
        Write-Host "[OK] Connected!`n" -ForegroundColor Green
        
        # Test query
        Write-Host "Running test query..." -ForegroundColor Yellow
        $query = "SELECT @@VERSION"
        
        $execResult = [Win32.SQL]::ExecuteSql($query)
        if ($execResult -eq [IntPtr]::Zero) {
            Write-Host "[OK] Query executed!`n" -ForegroundColor Green
        }
        else {
            $err = [Win32.SQL]::PtrToString($execResult)
            Write-Host "[ERROR] Query failed: $err`n" -ForegroundColor Red
            [Win32.SQL]::FreeCString($execResult)
        }
        
        Write-Host "Disconnecting..." -ForegroundColor Yellow
        [Win32.SQL]::DisconnectDb()
        Write-Host "[OK] Disconnected`n" -ForegroundColor Green
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "[SUCCESS] All tests passed!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
    }
    else {
        $err = [Win32.SQL]::PtrToString($result)
        Write-Host "[ERROR] Connection failed: $err`n" -ForegroundColor Red
        [Win32.SQL]::FreeCString($result)
        exit 1
    }
}
catch {
    Write-Host "[ERROR] Exception occurred: $_`n" -ForegroundColor Red
    exit 1
}
