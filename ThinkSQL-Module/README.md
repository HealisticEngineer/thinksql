# ThinkSQL PowerShell Module

A PowerShell module for SQL Server that provides automatic SQL processing features including SNAPSHOT isolation for SELECT queries and automatic primary key injection for CREATE TABLE statements.

## Installation

### Option 1: Copy Module to PowerShell Modules Directory

```powershell
# Find your modules directory
$modulePath = $env:PSModulePath -split ';' | Select-Object -First 1

# Copy the entire ThinkSQL-Module folder
Copy-Item -Path ".\ThinkSQL-Module" -Destination "$modulePath\ThinkSQL" -Recurse

# Import the module
Import-Module ThinkSQL
```

### Option 2: Import Directly

```powershell
Import-Module .\ThinkSQL-Module\ThinkSQL.psd1
```

## Quick Start

```powershell
# Import the module
Import-Module ThinkSQL

# Connect to SQL Server
Connect-ThinkSQLConnection -Server "localhost" -Database "master" -Username "sa" -Password "YourPassword"

# Execute a SELECT query (returns PowerShell objects)
$results = Invoke-ThinkSQL "SELECT * FROM sys.databases"
$results | Format-Table

# Create a table (automatically adds primary key)
Invoke-ThinkSQL "CREATE TABLE Users (Name VARCHAR(100), Email VARCHAR(100))"

# Insert data
Invoke-ThinkSQL "INSERT INTO Users (Name, Email) VALUES ('John Doe', 'john@example.com')"

# Query the data
$users = Invoke-ThinkSQL "SELECT * FROM Users"
$users

# Close connection
Close-ThinkSQLConnection
```

## Cmdlets

### Connect-ThinkSQLConnection

Establishes a connection to SQL Server.

**Parameters:**
- `-Server` - SQL Server hostname (default: localhost)
- `-Database` - Database name (default: master)
- `-Username` - SQL authentication username (default: sa)
- `-Password` - SQL authentication password (prompts if not provided)
- `-ConnectionString` - Full connection string (overrides other parameters)

**Examples:**

```powershell
# Basic connection
Connect-ThinkSQLConnection -Server "localhost" -Database "master" -Username "sa" -Password "MyPassword"

# Using connection string
Connect-ThinkSQLConnection -ConnectionString "server=localhost;user id=sa;password=MyPass;database=master"

# Interactive password prompt
Connect-ThinkSQLConnection -Server "localhost" -Username "sa"
```

### Invoke-ThinkSQL

Executes SQL statements with automatic processing.

**Features:**
- SELECT queries automatically use SNAPSHOT isolation level
- CREATE TABLE statements automatically add `ID INT PRIMARY KEY IDENTITY(1,1)` if no primary key exists
- SELECT queries return results as PowerShell objects (or JSON with `-AsJson`)

**Parameters:**
- `-Query` - The SQL statement to execute
- `-AsJson` - Return SELECT results as raw JSON

**Examples:**

```powershell
# SELECT query (returns PowerShell objects)
$data = Invoke-ThinkSQL "SELECT @@VERSION AS Version"
$data.Version

# SELECT with JSON output
$json = Invoke-ThinkSQL "SELECT * FROM Users" -AsJson

# CREATE TABLE (auto-adds primary key)
Invoke-ThinkSQL "CREATE TABLE Products (Name VARCHAR(100), Price DECIMAL(10,2))"

# INSERT
Invoke-ThinkSQL "INSERT INTO Products (Name, Price) VALUES ('Widget', 19.99)"

# UPDATE
Invoke-ThinkSQL "UPDATE Products SET Price = 24.99 WHERE Name = 'Widget'"

# DELETE
Invoke-ThinkSQL "DELETE FROM Products WHERE Price > 100"
```

### Get-ThinkSQLConnection

Returns information about the current connection.

**Example:**

```powershell
$conn = Get-ThinkSQLConnection
if ($conn) {
    Write-Host "Connected to $($conn.Server)/$($conn.Database)"
}
```

### Close-ThinkSQLConnection

Closes the active SQL Server connection.

**Example:**

```powershell
Close-ThinkSQLConnection
```

## Automatic SQL Processing

### SNAPSHOT Isolation

All SELECT queries automatically execute with SNAPSHOT isolation level, which:
- Prevents reads from being blocked by writes
- Provides consistent point-in-time views of data
- Improves concurrency in high-traffic scenarios

```powershell
# This SELECT is not blocked by long-running UPDATEs
$data = Invoke-ThinkSQL "SELECT * FROM LargeTable"
```

### Auto Primary Key

CREATE TABLE statements without a PRIMARY KEY automatically get:
```sql
ID INT PRIMARY KEY IDENTITY(1,1)
```

```powershell
# Original query
Invoke-ThinkSQL "CREATE TABLE Users (Name VARCHAR(100))"

# Actual executed SQL
# CREATE TABLE Users (ID INT PRIMARY KEY IDENTITY(1,1), Name VARCHAR(100))
```

## Advanced Examples

### Working with Results

```powershell
# Get results as objects
$databases = Invoke-ThinkSQL "SELECT name, database_id FROM sys.databases"

# Access properties
foreach ($db in $databases) {
    Write-Host "$($db.name) has ID $($db.database_id)"
}

# Filter and sort
$databases | Where-Object { $_.database_id -gt 4 } | Sort-Object name
```

### Error Handling

```powershell
try {
    Connect-ThinkSQLConnection -Server "localhost" -Username "sa" -Password "wrong"
}
catch {
    Write-Error "Connection failed: $_"
}

try {
    Invoke-ThinkSQL "SELECT * FROM NonExistentTable"
}
catch {
    Write-Error "Query failed: $_"
}
```

### Session Management

```powershell
# Check if connected
$conn = Get-ThinkSQLConnection
if (-not $conn) {
    Connect-ThinkSQLConnection -Server "localhost" -Username "sa" -Password "MyPass"
}

# Execute queries
$result = Invoke-ThinkSQL "SELECT @@VERSION"

# Always close connection when done
Close-ThinkSQLConnection
```

## Requirements

- PowerShell 5.1 or later
- SQL Server instance accessible via SQL authentication
- ThinkSQL.dll (included in module directory)

## Module Structure

```
ThinkSQL-Module/
├── ThinkSQL.psd1       # Module manifest
├── ThinkSQL.psm1       # Module implementation
├── ThinkSQL.dll        # C shared library (CGO)
└── README.md           # This file
```

## Troubleshooting

### "ThinkSQL.dll not found"
Ensure ThinkSQL.dll is in the same directory as the .psm1 file.

### "Failed to connect"
- Verify SQL Server is running
- Check server name, username, and password
- Ensure SQL Server authentication is enabled
- Check firewall settings

### "Type already loaded" errors
If you rebuild the DLL, start a fresh PowerShell session:
```powershell
pwsh -NoProfile
Import-Module .\ThinkSQL-Module\ThinkSQL.psd1
```

## License

See repository LICENSE file.
