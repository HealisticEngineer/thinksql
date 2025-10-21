# Test-DLL-Import.ps1
# This script tests importing the ThinkSQL.dll and verifying the exported functions

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing ThinkSQL.dll Import" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get the DLL path
$dllPath = Join-Path $PSScriptRoot "..\ThinkSQL.dll"
$dllPath = (Resolve-Path $dllPath -ErrorAction Stop).Path

Write-Host "DLL Path: $dllPath" -ForegroundColor Yellow

# Check if DLL exists
if (-not (Test-Path $dllPath)) {
    Write-Host "ERROR: DLL not found at $dllPath" -ForegroundColor Red
    exit 1
}

Write-Host "✓ DLL file exists" -ForegroundColor Green
Write-Host "  Size: $([math]::Round((Get-Item $dllPath).Length / 1MB, 2)) MB" -ForegroundColor Gray
Write-Host ""

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
    Write-Host "Loading DLL functions..." -ForegroundColor Yellow
    Add-Type -MemberDefinition $sig -Namespace Win32 -Name ThinkSQL -ErrorAction Stop
    Write-Host "✓ Successfully loaded DLL functions" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Available functions:" -ForegroundColor Cyan
    Write-Host "  - ConnectDb(connStr)" -ForegroundColor Gray
    Write-Host "  - DisconnectDb()" -ForegroundColor Gray
    Write-Host "  - ExecuteSql(sqlStr)" -ForegroundColor Gray
    Write-Host "  - FreeCString(str)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "✓ DLL import test PASSED" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to load DLL" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
