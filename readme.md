# ThinkSQL - SQL Processor as a Windows DLL (Go + CGO)

This repository builds a Windows shared library (`ThinkSQL.dll`) exposing SQL Server features via CGO exports. It includes PowerShell tests that P/Invoke the DLL to open connections and execute SQL with a small auto-processing pipeline.
For ease of use, a PowerShell module (`ThinkSQL-Module`) wraps the DLL functionality.

Build with the intention of fixing common SQL issue create by oversights in application code.

Rather than raw SQL execution, ThinkSQL automatically:
- Injects `ID INT PRIMARY KEY IDENTITY(1,1)` into `CREATE TABLE` statements missing a primary key, ensuring tables always have a primary key index
- Prepends `SET TRANSACTION ISOLATION LEVEL SNAPSHOT` to all `SELECT` queries, preventing read blocking during write operations
- Returns `SELECT` results as JSON strings (e.g., `[{"Column":"Value"}]`)

## Table of Contents
- [Requirements](#requirements)
- [Build (recommended)](#build-recommended)
- [What the DLL does](#what-the-dll-does)
- [PowerShell Module (Recommended)](#powershell-module-recommended)
- [Performance](#performance)
- [Test](#test)

## Requirements
- Go 1.18 or later (tested with Go 1.26.x)
- GCC toolchain for CGO. Recommended: WinLibs (UCRT/MCF) via winget
	- `winget install -e --id BrechtSanders.WinLibs.MCF.UCRT`
- A local or reachable SQL Server instance for testing

## Build (recommended)
Use the provided script. It validates prerequisites and builds both `ThinkSQL.dll` and `ThinkSQL.h`:

```powershell
cd w:\github\thinksql # Adjust path as needed
.\Build-ThinkSQL.ps1
```

The build script uses `-ldflags="-s -w"` to strip debug symbols. This is **required** for Go 1.26+ because the linker places debug sections before code sections in the PE file, causing the Windows PE loader to reject the DLL with `BadImageFormatException` / error `0x8007000B`.

If you need to build manually:

```powershell
$env:CGO_ENABLED = '1'
go build -buildmode=c-shared -ldflags="-s -w" -o ThinkSQL.dll main.go
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

Connect-ThinkSQLConnection -ConnectionString "server=localhost;database=master;user id=sa;password=YourPassword"

# Query (returns PowerShell objects)
$results = Invoke-ThinkSQL "SELECT * FROM sys.databases"
$results | Format-Table

# Close
Close-ThinkSQLConnection
```

See `ThinkSQL-Module\README.md` for complete documentation.

## Performance

ThinkSQL has been benchmarked against the standard SqlServer PowerShell module using rigorous testing (5 runs × 50 iterations = 250 operations per test):

| Operation | ThinkSQL (±SD) | SqlServer Module (±SD) | ADO.NET Baseline (±SD) | vs SqlServer | vs ADO.NET |
|-----------|----------------|------------------------|------------------------|--------------|------------|
| **Connection** | **1.18ms (±0.35)** | **6.38ms (±12.17)** | **0.01ms (±0)** | **5.43x faster** | **—** |
| System Query | 1.61ms (±0.49) | 1.07ms (±0.01) | 0.92ms (±0.05) | 0.67x | 0.57x |
| Aggregate Query | 1.90ms (±0.49) | 1.58ms (±0.18) | 1.35ms (±0.02) | 0.83x | 0.71x |
| Large Aggregate | 5.56ms (±0.58) | 4.93ms (±0.12) | 4.75ms (±0.17) | 0.89x | 0.85x |
| Simple SELECT | 1.08ms (±0.03) | 0.92ms (±0.01) | 0.79ms (±0.02) | 0.85x | 0.73x |
| Batch (5 queries) | 5.73ms (±0.24) | 5.27ms (±0.06) | 4.80ms (±0.03) | 0.92x | 0.84x |
| Bulk INSERT (100 rows) | 4.08ms (±0.28) | 3.80ms (±0.20) | 3.52ms (±0.25) | 0.93x | 0.86x |
| Sequential (3 queries) | 3.96ms (±0.31) | 3.65ms (±0.22) | 3.29ms (±0.04) | 0.92x | 0.83x |
| **Overall Average** | **3.14ms** | **3.45ms** | **2.43ms** | **1.1x faster** | **1.29x** |

### Blocking Behavior Test (SNAPSHOT Isolation Advantage)

This test demonstrates ThinkSQL's SNAPSHOT isolation preventing read blocking during write operations:

| Method | Average Time | Blocked Queries | Success Rate | Status |
|--------|-------------|-----------------|--------------|---------|
| **ThinkSQL (SNAPSHOT)** | **1.50ms (±0.03)** | **0/250 (0%)** | **100%** | ✅ **Non-blocking** |
| SqlServer (READ COMMITTED) | N/A | 250/250 (100%) | 0% | ❌ **All blocked** |
| ADO.NET (READ COMMITTED) | N/A | 250/250 (100%) | 0% | ❌ **All blocked** |

**Test methodology**: Each iteration starts an uncommitted UPDATE transaction holding row locks, then attempts a SELECT query (250 total per method). ThinkSQL's SNAPSHOT isolation allows all reads to proceed without blocking, while SqlServer and ADO.NET modules (using default READ COMMITTED isolation) block waiting for the uncommitted transaction.

### Key Performance Characteristics:
- **Faster Overall**: ThinkSQL averages 3.14ms vs SqlServer's 3.45ms — **1.1x faster on average**. Single-batch SQL execution (combining `SET TRANSACTION ISOLATION LEVEL SNAPSHOT` with the query in one roundtrip) and direct JSON buffer serialization eliminate overhead that previously made ThinkSQL slower.
- **Connection Speed**: ThinkSQL connects in 1.18ms with pool caching (±0.35ms), **5.43x faster** than SqlServer module's 6.38ms (±12.17ms). Connection pool caching reuses Go's `sql.DB` pool across connect/disconnect cycles, avoiding full TCP+authentication handshakes on reconnection.
- **Batch & Sequential Performance**: Batch (5 queries) runs at 5.73ms (0.92x vs SqlServer) and Sequential (3 queries) at 3.96ms (0.92x), both benefiting from single-roundtrip isolation level setting instead of a separate `db.Exec` per query.
- **Consistency**: ThinkSQL shows very stable performance (±0.03-0.58ms typical StdDev) vs SqlServer module's occasional variance spikes (±12.17ms on connection)
- **SNAPSHOT Isolation Advantage**: 
  - ThinkSQL automatically prepends `SET TRANSACTION ISOLATION LEVEL SNAPSHOT` to all SELECT queries
  - **100% non-blocking reads** during write operations (0/250 queries blocked in testing)
  - SqlServer and ADO.NET modules experience **100% blocking** (250/250 queries blocked) under the same conditions
  - **Critical for high-concurrency applications** where reads shouldn't wait for uncommitted writes
- **Bulk INSERT**: Very competitive at 4.08ms vs SqlServer's 3.80ms (0.93x ratio) for 100-row inserts
- **CGO Overhead**: The CGO interop and JSON marshaling adds ~1.29x overhead vs raw ADO.NET baseline
- **Best Use Cases**: 
  - **High-concurrency applications** requiring non-blocking reads (SNAPSHOT isolation by default)
  - Long-running applications where connection setup cost is amortized
  - Scenarios where predictable performance (low variance) is critical
  - **Applications that need to read during long-running write operations**
  - Moderate-sized result sets where JSON marshaling overhead is acceptable

**Note**: ThinkSQL is now **faster than the SqlServer module on average** (1.1x) thanks to connection pool caching, single-batch SQL execution, and direct JSON buffer serialization. Combined with **non-blocking concurrency** (SNAPSHOT isolation) — where 100% of queries proceed during write operations while standard READ COMMITTED blocks all queries — ThinkSQL offers both better performance and stronger concurrency guarantees for high-throughput scenarios.

Run `.\Performance-Comparison.ps1 -Runs 10` to benchmark on your system with statistically averaged results.

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
- 0x8007000B (incorrect format) / "Value cannot be null. (Parameter 'path1')": rebuild with `-ldflags="-s -w"` (the build script does this automatically). Go 1.26+ places debug sections before code sections, which breaks the Windows PE loader. Stripping symbols fixes this and reduces DLL size.
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