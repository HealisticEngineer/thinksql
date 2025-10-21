# ThinkSQL Test Connection Scripts

This folder contains PowerShell scripts to test the ThinkSQL.dll functionality.

## Prerequisites

1. **Go** - Install from [golang.org](https://golang.org/dl/)
2. **GCC** (for CGO) - Will be auto-installed by Build-ThinkSQL.ps1 if not present
3. **SQL Server** - A running SQL Server instance to test connections

## Scripts

### 1. Build-ThinkSQL.ps1 (in parent directory)
Compiles the Go code into a Windows DLL.

```powershell
cd w:\github\ThinkSQL
.\Build-ThinkSQL.ps1
```

### 2. Test-DLL-Import.ps1
Tests that the DLL can be loaded and functions are accessible.

```powershell
cd w:\github\ThinkSQL\TestConnection
.\Test-DLL-Import.ps1
```

This script:
- Verifies the DLL file exists
- Loads the DLL into PowerShell via C# P/Invoke
- Confirms all exported functions are accessible
- Does NOT connect to SQL Server

### 3. Test-SQL-Connection.ps1
Tests actual SQL Server connectivity using the ConnectDb function.

```powershell
cd w:\github\ThinkSQL\TestConnection

# Interactive (will prompt for password)
.\Test-SQL-Connection.ps1 -Server "localhost" -Database "master" -Username "sa"

# With all parameters
.\Test-SQL-Connection.ps1 -Server "localhost" -Database "master" -Username "sa" -Password "YourPassword"
```

This script:
- Loads the DLL
- Connects to SQL Server using the ConnectDb function
- Executes a test query (SELECT @@VERSION)
- Disconnects properly
- Reports success or failure

### Parameters for Test-SQL-Connection.ps1

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-Server` | No | localhost | SQL Server hostname or IP |
| `-Database` | No | master | Database name to connect to |
| `-Username` | No | sa | SQL Server username |
| `-Password` | No | (prompt) | SQL Server password (will prompt if not provided) |

## Testing Workflow

1. **Build the DLL**
   ```powershell
   cd w:\github\ThinkSQL
   .\Build-ThinkSQL.ps1
   ```

2. **Test DLL Import**
   ```powershell
   cd TestConnection
   .\Test-DLL-Import.ps1
   ```

3. **Test SQL Connection**
   ```powershell
   .\Test-SQL-Connection.ps1 -Server "localhost" -Username "sa"
   # Enter password when prompted
   ```

## Expected Output

### Successful Connection
```
========================================
Testing SQL Server Connection via ThinkSQL.dll
========================================

Configuration:
  DLL Path: W:\github\ThinkSQL\ThinkSQL.dll
  Server: localhost
  Database: Master
  Username: SA
  Password: *****

Loading DLL...
[OK] DLL loaded successfully

Attempting to connect to SQL Server...
INFO: Database connection established successfully.
[OK] Successfully connected to SQL Server!

Testing SQL execution...
INFO: Prepended SET TRANSACTION ISOLATION LEVEL SNAPSHOT to SELECT statement.
INFO: Successfully executed SQL: SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
SELECT @@VERSION AS Version
[OK] SQL query executed successfully!
  Query: SELECT @@VERSION AS Version

Disconnecting...
INFO: Database connection closed.
[OK] Disconnected successfully

========================================
[OK] ALL TESTS PASSED
========================================

Connection test completed successfully!
```

### Failed Connection
```
[ERROR] Connection failed: ERROR: Failed to connect to database: ...
```

## Available Scripts

All scripts now use the same working P/Invoke pattern:

1. **Quick-Test.ps1** - Minimal, hardcoded test (quickest)
2. **Test-SQL-Connection-Simple.ps1** - Simple with parameters
3. **Test-SQL-Connection.ps1** - Full-featured with detailed output
4. **Test-DLL-Import.ps1** - DLL loading test only (no SQL connection)

## Troubleshooting

### "DLL not found"
- Make sure you've run `Build-ThinkSQL.ps1` first
- Check that `ThinkSQL.dll` exists in the parent directory

### "GCC not found"
- Run `Build-ThinkSQL.ps1` which will auto-install GCC via winget
- Or manually install MinGW-w64 from [winlibs.com](https://winlibs.com/)

### "Connection failed"
- Verify SQL Server is running: `.\Confirm_Sql_Running.ps1`
- Check server name, username, and password
- Ensure SQL Server authentication is enabled (not just Windows auth)
- Check firewall settings

### "Failed to load DLL"
- Ensure you're running PowerShell (not CMD)
- Try running PowerShell as Administrator
- Check that the DLL is not corrupted (rebuild it)

## Connection String Format

The DLL uses the go-mssqldb driver connection string format:
```
server=hostname;user id=username;password=password;database=dbname
```

Additional parameters can be added as needed (see go-mssqldb documentation).
