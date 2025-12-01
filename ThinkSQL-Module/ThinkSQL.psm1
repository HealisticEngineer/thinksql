# ThinkSQL PowerShell Module
# Provides convenient cmdlets for working with ThinkSQL.dll

$ModulePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$DllPath = Join-Path $ModulePath "ThinkSQL.dll"

# Verify DLL exists
if (-not (Test-Path $DllPath)) {
    throw "ThinkSQL.dll not found at: $DllPath. Please ensure the DLL is in the module directory."
}

# Define P/Invoke signatures
$TypeDefinition = @"
using System;
using System.Runtime.InteropServices;

namespace ThinkSQL {
    public class Native {
        [DllImport("$($DllPath.Replace('\','\\'))", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern IntPtr ConnectDb([MarshalAs(UnmanagedType.LPStr)] string connStr);

        [DllImport("$($DllPath.Replace('\','\\'))", CallingConvention = CallingConvention.Cdecl)]
        public static extern void DisconnectDb();

        [DllImport("$($DllPath.Replace('\','\\'))", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern IntPtr ExecuteSql([MarshalAs(UnmanagedType.LPStr)] string sqlStr);

        [DllImport("$($DllPath.Replace('\','\\'))", CallingConvention = CallingConvention.Cdecl)]
        public static extern void FreeCString(IntPtr str);

        public static string PtrToString(IntPtr ptr) {
            if (ptr == IntPtr.Zero) return null;
            return Marshal.PtrToStringAnsi(ptr);
        }
    }
}
"@

# Load the type if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'ThinkSQL.Native').Type) {
    Add-Type -TypeDefinition $TypeDefinition
}

# Global connection state
$script:ThinkSQLConnection = $null

<#
.SYNOPSIS
Connects to a SQL Server database using ThinkSQL.

.DESCRIPTION
Establishes a connection to SQL Server. The connection remains active until Close-ThinkSQLConnection is called.

.PARAMETER Server
The SQL Server hostname or IP address. Default: localhost

.PARAMETER Database
The database name to connect to. Default: master

.PARAMETER Username
SQL Server authentication username. Default: sa

.PARAMETER Password
SQL Server authentication password.

.PARAMETER ConnectionString
Full connection string. If provided, other parameters are ignored.

.EXAMPLE
Connect-ThinkSQLConnection -Server "localhost" -Database "master" -Username "sa" -Password "MyPassword"

.EXAMPLE
Connect-ThinkSQLConnection -ConnectionString "server=localhost;user id=sa;password=MyPass;database=master"
#>
function Connect-ThinkSQLConnection {
    [CmdletBinding(DefaultParameterSetName='Parameters')]
    param(
        [Parameter(ParameterSetName='Parameters')]
        [string]$Server = "localhost",
        
        [Parameter(ParameterSetName='Parameters')]
        [string]$Database = "master",
        
        [Parameter(ParameterSetName='Parameters')]
        [string]$Username = "sa",
        
        [Parameter(ParameterSetName='Parameters')]
        [string]$Password,
        
        [Parameter(ParameterSetName='ConnectionString', Mandatory=$true)]
        [string]$ConnectionString
    )
    
    # Close existing connection if any
    if ($script:ThinkSQLConnection) {
        Close-ThinkSQLConnection
    }
    
    # Build connection string
    if ($PSCmdlet.ParameterSetName -eq 'ConnectionString') {
        $connStr = $ConnectionString
    }
    else {
        if ([string]::IsNullOrEmpty($Password)) {
            $securePassword = Read-Host "Enter password for $Username" -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        }
        
        $connStr = "server=$Server;user id=$Username;password=$Password;database=$Database;encrypt=disable;TrustServerCertificate=true"
    }
    
    # Attempt connection
    $resultPtr = [ThinkSQL.Native]::ConnectDb($connStr)
    
    if ($resultPtr -ne [IntPtr]::Zero) {
        $errorMsg = [ThinkSQL.Native]::PtrToString($resultPtr)
        [ThinkSQL.Native]::FreeCString($resultPtr)
        throw "Failed to connect: $errorMsg"
    }
    
    $script:ThinkSQLConnection = @{
        Server = $Server
        Database = $Database
        Username = $Username
        Connected = $true
    }
    
    Write-Verbose "Connected to SQL Server: $Server/$Database"
}

<#
.SYNOPSIS
Closes the active ThinkSQL connection.

.DESCRIPTION
Closes the connection to SQL Server and cleans up resources.

.EXAMPLE
Close-ThinkSQLConnection
#>
function Close-ThinkSQLConnection {
    [CmdletBinding()]
    param()
    
    if ($script:ThinkSQLConnection) {
        [ThinkSQL.Native]::DisconnectDb()
        $script:ThinkSQLConnection = $null
        Write-Verbose "Connection closed"
    }
}

<#
.SYNOPSIS
Executes a SQL statement using ThinkSQL.

.DESCRIPTION
Executes SQL statements with automatic processing:
- SELECT queries return results as PowerShell objects with SNAPSHOT isolation
- CREATE TABLE statements automatically add a primary key if missing
- Other statements execute normally

.PARAMETER Query
The SQL statement to execute.

.PARAMETER AsJson
Return SELECT results as raw JSON instead of PowerShell objects.

.EXAMPLE
Invoke-ThinkSQL -Query "SELECT * FROM Users"

.EXAMPLE
Invoke-ThinkSQL -Query "CREATE TABLE Products (Name VARCHAR(100))"

.EXAMPLE
Invoke-ThinkSQL -Query "INSERT INTO Users (Name, Email) VALUES ('John', 'john@example.com')"
#>
function Invoke-ThinkSQL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Query,
        
        [switch]$AsJson
    )
    
    if (-not $script:ThinkSQLConnection) {
        throw "Not connected to SQL Server. Use Connect-ThinkSQLConnection first."
    }
    
    $resultPtr = [ThinkSQL.Native]::ExecuteSql($Query)
    
    if ($resultPtr -eq [IntPtr]::Zero) {
        # Non-SELECT query succeeded
        Write-Verbose "SQL executed successfully"
        return
    }
    
    # Get the result (either JSON data or error message)
    $result = [ThinkSQL.Native]::PtrToString($resultPtr)
    [ThinkSQL.Native]::FreeCString($resultPtr)
    
    # Try to parse as JSON (SELECT results)
    try {
        $jsonResult = $result | ConvertFrom-Json
        
        if ($AsJson) {
            return $result
        }
        else {
            return $jsonResult
        }
    }
    catch {
        # It's an error message
        throw $result
    }
}

<#
.SYNOPSIS
Gets the current ThinkSQL connection status.

.DESCRIPTION
Returns information about the active connection, or $null if not connected.

.EXAMPLE
Get-ThinkSQLConnection
#>
function Get-ThinkSQLConnection {
    [CmdletBinding()]
    param()
    
    return $script:ThinkSQLConnection
}

# Export module members
Export-ModuleMember -Function @(
    'Connect-ThinkSQLConnection',
    'Close-ThinkSQLConnection',
    'Invoke-ThinkSQL',
    'Get-ThinkSQLConnection'
)
