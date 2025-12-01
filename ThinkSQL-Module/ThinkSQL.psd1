@{
    # Module information
    ModuleVersion = '1.0.1'
    GUID = '5e8f7c9a-4b3d-4e2f-9a1c-6d8e4f7b2a9c'
    Author = 'John Hall'
    Copyright = '(c) 2025 John Hall. All rights reserved.'
    Description = 'ThinkSQL Project PowerShell module for interacting with SQL Server using ThinkSQL.dll with automatic SQL processing (SNAPSHOT isolation, auto-primary keys)'
    
    # Module components
    RootModule = 'ThinkSQL.psm1'
    
    # Minimum PowerShell version
    PowerShellVersion = '5.1'
    
    # Functions to export
    FunctionsToExport = @(
        'Connect-ThinkSQLConnection',
        'Close-ThinkSQLConnection',
        'Invoke-ThinkSQL',
        'Get-ThinkSQLConnection'
    )
    
    # Cmdlets to export
    CmdletsToExport = @()
    
    # Variables to export
    VariablesToExport = @()
    
    # Aliases to export
    AliasesToExport = @()
    
    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('SQL', 'SQLServer', 'Database', 'ThinkSQL', 'MSSQL')
            LicenseUri = ''
            ProjectUri = 'https://github.com/HealisticEngineer/thinksql'
            ReleaseNotes = @'
Version 1.0.0
- Initial release
- Connect/disconnect to SQL Server
- Execute SQL with automatic processing
- SELECT queries use SNAPSHOT isolation
- CREATE TABLE auto-adds primary key
- Returns SELECT results as PowerShell objects or JSON
'@
        }
    }
}
