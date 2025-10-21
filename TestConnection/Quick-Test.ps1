# Quick-Test.ps1
# Minimal test of ThinkSQL.dll

$dllPath = "W:\github\ThinkSQL\ThinkSQL.dll"

Write-Host "Testing: $dllPath`n"

if (-not (Test-Path $dllPath)) {
    Write-Host "DLL not found!" -ForegroundColor Red
    exit 1
}

$sig = @'
[DllImport("W:\\github\\ThinkSQL\\ThinkSQL.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
public static extern IntPtr ConnectDb([MarshalAs(UnmanagedType.LPStr)] string connStr);

[DllImport("W:\\github\\ThinkSQL\\ThinkSQL.dll", CallingConvention = CallingConvention.Cdecl)]
public static extern void DisconnectDb();

[DllImport("W:\\github\\ThinkSQL\\ThinkSQL.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
public static extern IntPtr ExecuteSql([MarshalAs(UnmanagedType.LPStr)] string sqlStr);

[DllImport("W:\\github\\ThinkSQL\\ThinkSQL.dll", CallingConvention = CallingConvention.Cdecl)]
public static extern void FreeCString(IntPtr str);

public static string PtrToString(IntPtr ptr) {
    if (ptr == IntPtr.Zero) return null;
    return System.Runtime.InteropServices.Marshal.PtrToStringAnsi(ptr);
}
'@

Add-Type -MemberDefinition $sig -Namespace Win32 -Name ThinkSQL

$connStr = "server=localhost;user id=SA;password=NeverSafe2Day!;database=master"

Write-Host "Connecting..." -ForegroundColor Yellow
$result = [Win32.ThinkSQL]::ConnectDb($connStr)

if ($result -eq [IntPtr]::Zero) {
    Write-Host "[OK] Connected!" -ForegroundColor Green
    
    Write-Host "Testing query..." -ForegroundColor Yellow
    $execResult = [Win32.ThinkSQL]::ExecuteSql("SELECT @@VERSION")
    
    if ($execResult -eq [IntPtr]::Zero) {
        Write-Host "[OK] Query executed!" -ForegroundColor Green
    }
    else {
        $err = [Win32.ThinkSQL]::PtrToString($execResult)
        Write-Host "[ERROR] $err" -ForegroundColor Red
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
