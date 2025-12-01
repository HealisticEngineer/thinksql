# Quick-Test.ps1
# Minimal test of ThinkSQL.dll

# Get the directory of this script
$dllPath = Join-Path $PSScriptRoot "..\ThinkSQL.dll"
$dllPath = (Resolve-Path $dllPath -ErrorAction Stop).Path

Write-Host "Testing: $dllPath`n"

if (-not (Test-Path $dllPath)) {
    Write-Host "DLL not found!" -ForegroundColor Red
    exit 1
}

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
    # Type might already exist from previous run - that's okay
    Write-Host "Note: Type already loaded (this is normal)" -ForegroundColor Gray
}

$connStr = "server=localhost;user id=SA;password=NeverSafe2Day!;database=master;encrypt=disable;TrustServerCertificate=true"

Write-Host "Connecting..." -ForegroundColor Yellow
$result = [Win32.ThinkSQL]::ConnectDb($connStr)

if ($result -eq [IntPtr]::Zero) {
    Write-Host "[OK] Connected!" -ForegroundColor Green
    
    Write-Host "Testing query..." -ForegroundColor Yellow
    $execResult = [Win32.ThinkSQL]::ExecuteSql("SELECT @@VERSION AS ServerVersion")
    
    if ($execResult -eq [IntPtr]::Zero) {
        Write-Host "[ERROR] Expected JSON results but got null" -ForegroundColor Red
    }
    else {
        $jsonResults = [Win32.ThinkSQL]::PtrToString($execResult)
        
        # Check if it's an error message
        if ($jsonResults.StartsWith("ERROR:")) {
            Write-Host "[ERROR] $jsonResults" -ForegroundColor Red
        }
        else {
            Write-Host "[OK] Query executed!" -ForegroundColor Green
            Write-Host "Results (JSON):" -ForegroundColor Cyan
            
            # Pretty print JSON
            try {
                $jsonObj = $jsonResults | ConvertFrom-Json
                $jsonObj | Format-Table -AutoSize
                Write-Host "Raw JSON: $jsonResults" -ForegroundColor Gray
            }
            catch {
                Write-Host $jsonResults -ForegroundColor White
            }
        }
        
        [Win32.ThinkSQL]::FreeCString($execResult)
    }
    
    Write-Host "Disconnecting..." -ForegroundColor Yellow
    [Win32.ThinkSQL]::DisconnectDb()
    Write-Host "[OK] Done!" -ForegroundColor Green
}
else {
    $err = [Win32.ThinkSQL]::PtrToString($result)
    Write-Host "[ERROR] $err" -ForegroundColor Red
    [Win32.ThinkSQL]::FreeCString($result)
}
