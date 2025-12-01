# ThinkSQL - SQL Processor as a Windows DLL (Go + CGO)

This repository builds a Windows shared library (`ThinkSQL.dll`) exposing SQL Server features via CGO exports. It includes PowerShell tests that P/Invoke the DLL to open connections and execute SQL with a small auto-processing pipeline.

## Requirements
- Go 1.18 or later (tested with Go 1.25.x)
- GCC toolchain for CGO. Recommended: WinLibs (UCRT/MCF) via winget
	- `winget install -e --id BrechtSanders.WinLibs.MCF.UCRT`
- A local or reachable SQL Server instance for testing

## Build (recommended)
Use the provided script. It validates prerequisites and builds both `ThinkSQL.dll` and `ThinkSQL.h`:

```powershell
cd w:\github\thinksql
.\Build-ThinkSQL.ps1
```

If you encounter loader errors (0x8007000B) or interop issues, rebuild explicitly with WinLibs GCC:

```powershell
# Use WinLibs toolchain explicitly
$env:CC  = 'C:\Users\<you>\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.MCF.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin\gcc.exe'
$env:CXX = 'C:\Users\<you>\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.MCF.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin\g++.exe'
$env:CGO_ENABLED = '1'
$env:GOOS = 'windows'
$env:GOARCH = 'amd64'
go build -buildmode=c-shared -o ThinkSQL.dll main.go
```

Output artifacts:
- `ThinkSQL.dll` — the shared library
- `ThinkSQL.h` — C header with exported signatures

## What the DLL does
- Global connection pool (package-level `var db *sql.DB`)
- C exports (Cdecl) defined in `main.go`:
	- `ConnectDb(char* connStr) -> char*` returns null on success or error string pointer (must free)
	- `DisconnectDb(void)`
	- `ExecuteSql(char* sql) -> char*` returns:
		- For SELECT queries: JSON string with results (must free) e.g., `[{"Column":"Value"}]`
		- For non-SELECT queries: null on success or error string pointer (must free)
	- `FreeCString(char*)`
- SQL auto-processing:
	- `CREATE TABLE` — injects `ID INT PRIMARY KEY IDENTITY(1,1)` if no PK present
	- `SELECT` — prepends `SET TRANSACTION ISOLATION LEVEL SNAPSHOT;` and returns query results as JSON

## PowerShell Module (Recommended)

The easiest way to use ThinkSQL is via the PowerShell module:

```powershell
# Import the module
Import-Module .\ThinkSQL-Module\ThinkSQL.psd1

# Connect
Connect-ThinkSQLConnection -Server "localhost" -Username "sa" -Password "YourPassword"

# Query (returns PowerShell objects)
$results = Invoke-ThinkSQL "SELECT * FROM sys.databases"
$results | Format-Table

# Close
Close-ThinkSQLConnection
```

See `ThinkSQL-Module\README.md` for complete documentation.

## Test
PowerShell scripts under `TestConnection/` validate the DLL end to end.

Quickest path:
```powershell
cd w:\github\thinksql
.\Build-ThinkSQL.ps1

# Test the PowerShell module
.\Test-ThinkSQL-Module.ps1

# Or test the DLL directly
cd .\TestConnection
.\Test-DLL-Import.ps1           # Verifies exported functions can load
.\Quick-Test.ps1                # Minimal connect + SELECT test
.\Test-SQL-Connection.ps1       # Full-featured test with output
```

By default, tests connect to `server=localhost;database=master;user id=SA`. For local/dev SQL Server TLS quirks, the scripts include:
```
encrypt=disable;TrustServerCertificate=true
```
in the connection string to avoid errors like `x509: negative serial number`. Adjust as needed for your environment.

Troubleshooting tips:
- 0x8007000B (incorrect format): ensure 64-bit PowerShell process and rebuild with WinLibs GCC as above.
- PowerShell 7 Add-Type issues ("Value cannot be null. (Parameter 'path1')"): the provided scripts use absolute, escaped DLL paths and work in PowerShell 7 and Windows PowerShell 64-bit.
- TLS handshake errors on local SQL: keep `encrypt=disable;TrustServerCertificate=true` for dev, or install a valid cert and enable strict TLS in prod.
- Missing runtime DLLs: with WinLibs builds this is uncommon; if needed, place required GCC runtime DLLs (e.g., `libstdc++-6.dll`, `libwinpthread-1.dll`, `libgcc_s_seh_64-1.dll`) beside `ThinkSQL.dll`.
- DLL changes not reflecting: PowerShell caches the loaded type. Start a fresh PowerShell session with `pwsh -NoProfile` or restart your current session to reload updated DLLs.

## Example P/Invoke (PowerShell)
See `TestConnection\Quick-Test.ps1` for a compact, working pattern:
```powershell
$sig = @"
[DllImport("$($dllPath.Replace('\\','\\\\'))", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
public static extern IntPtr ConnectDb([MarshalAs(UnmanagedType.LPStr)] string connStr);
[DllImport("$($dllPath.Replace('\\','\\\\'))", CallingConvention = CallingConvention.Cdecl)]
public static extern void DisconnectDb();
[DllImport("$($dllPath.Replace('\\','\\\\'))", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
public static extern IntPtr ExecuteSql([MarshalAs(UnmanagedType.LPStr)] string sqlStr);
[DllImport("$($dllPath.Replace('\\','\\\\'))", CallingConvention = CallingConvention.Cdecl)]
public static extern void FreeCString(IntPtr str);
"@
Add-Type -MemberDefinition $sig -Namespace Win32 -Name ThinkSQL
```

Important notes:
- For SELECT queries: `ExecuteSql` returns a JSON string with results. Parse it and then free it with `FreeCString`.
- For non-SELECT queries: `ExecuteSql` returns null on success.
- Always free any non-null pointers returned from `ConnectDb`/`ExecuteSql` with `FreeCString`.

## References
- Main code: `main.go`
- Build script: `Build-ThinkSQL.ps1`
- Tests: `TestConnection/`
- Driver: `github.com/denisenkom/go-mssqldb`